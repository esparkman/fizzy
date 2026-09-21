require "test_helper"

class CardTest < ActiveSupport::TestCase
  setup do
    Current.session = sessions(:david)
  end

  test "create assigns a number to the card" do
    user = users(:david)
    board = boards(:writebook)
    account = board.account
    card = nil

    assert_difference -> { account.reload.cards_count }, +1 do
      card = Card.create!(title: "Test", board: board, creator: user)
    end

    assert_equal account.reload.cards_count, card.number
  end

  test "assignment states" do
    assert cards(:logo).assigned_to?(users(:kevin))
    assert_not cards(:logo).assigned_to?(users(:david))
  end

  test "assignment toggling" do
    assert cards(:logo).assigned_to?(users(:kevin))

    assert_difference({ -> { cards(:logo).assignees.count } => -1, -> { Event.count } => +1 }) do
      cards(:logo).toggle_assignment users(:kevin)
    end
    assert_not cards(:logo).reload.assigned_to?(users(:kevin))
    unassign_event = Event.last
    assert_equal "card_unassigned", unassign_event.action
    assert_equal [ users(:kevin) ], unassign_event.assignees

    assert_difference %w[ cards(:logo).assignees.count Event.count ], +1 do
      cards(:logo).toggle_assignment users(:kevin)
    end
    assert cards(:logo).assigned_to?(users(:kevin))
    assign_event = Event.last
    assert_equal "card_assigned", assign_event.action
    assert_equal [ users(:kevin) ], assign_event.assignees
  end

  test "tagged states" do
    assert cards(:logo).tagged_with?(tags(:web))
    assert_not cards(:logo).tagged_with?(tags(:mobile))
  end

  test "tag toggling" do
    assert cards(:logo).tagged_with?(tags(:web))

    assert_difference "cards(:logo).taggings.count", -1 do
      cards(:logo).toggle_tag_with tags(:web).title
    end
    assert_not cards(:logo).tagged_with?(tags(:web))

    assert_difference "cards(:logo).taggings.count", +1 do
      cards(:logo).toggle_tag_with tags(:web).title
    end
    assert cards(:logo).tagged_with?(tags(:web))

    assert_difference %w[ cards(:logo).taggings.count Tag.count ], +1 do
      cards(:logo).toggle_tag_with "prioritized"
    end
    assert_equal "prioritized", cards(:logo).taggings.last.tag.title
  end

  test "closed" do
    assert_equal [ cards(:shipping) ], Card.closed
  end

  test "open" do
    assert_equal cards(:logo, :layout, :text, :buy_domain, :redesign_epic, :redesign_header, :private_board_card).to_set, accounts("37s").cards.open.to_set
    assert_equal cards(:radio, :paycheck, :unfinished_thoughts).to_set, accounts("initech").cards.open.to_set
  end

  test "card_unassigned" do
    assert_equal cards(:shipping, :text, :buy_domain, :redesign_epic, :redesign_header, :private_board_card).to_set, accounts("37s").cards.unassigned.to_set
  end

  test "assigned to" do
    assert_equal cards(:logo, :layout).to_set, Card.assigned_to(users(:jz)).to_set
  end

  test "assigned by" do
    assert_equal cards(:layout, :logo).to_set, Card.assigned_by(users(:david)).to_set
  end

  test "in board" do
    new_board = Board.create! name: "New Board", creator: users(:david)
    assert_equal cards(:logo, :shipping, :layout, :text, :buy_domain).to_set, Card.where(board: boards(:writebook)).to_set
    assert_empty Card.where(board: new_board)
  end

  test "tagged with" do
    assert_equal cards(:layout, :text), Card.tagged_with(tags(:mobile))
  end

  test "for published cards, it should set the default title 'Untitiled' when not provided" do
    card = boards(:writebook).cards.create!
    assert_nil card.title

    card.publish
    assert_equal "Untitled", card.reload.title
  end

  test "send back to triage when moved to a new board" do
    cards(:logo).update! column: columns(:writebook_in_progress)

    assert_changes -> { cards(:logo).reload.triaged? }, from: true, to: false do
      cards(:logo).update! board: boards(:private)
    end
  end

  test "an admin mover grants access to assignees when moving the card to a new board" do
    board = accounts("37s").boards.create!(name: "David's board", creator: users(:david), all_access: false)
    board.accesses.grant_to(users(:kevin)) # kevin can reach the board, but did not create it
    Current.session = sessions(:kevin) # admin, and a member of both the source and destination boards
    card = cards(:logo)
    assignee = users(:jz) # already assigned to the card via fixtures, no access to the destination board

    assert Current.user.admin?
    assert_not_equal Current.user, board.creator # authorized through the admin role, not the creator path
    assert board.accessible_to?(users(:kevin))
    assert_includes card.assignees, assignee
    assert_not board.accessible_to?(assignee)

    card.update!(board: board)
    assert_includes board.users.reload, assignee
  end

  test "a non-admin board creator grants access to assignees when moving the card to a new board" do
    Current.session = sessions(:david) # plain member, but the creator of the destination board
    board = accounts("37s").boards.create!(name: "David's board", creator: users(:david), all_access: false)
    card = cards(:logo)
    assignee = users(:jz) # already assigned to the card via fixtures, no access to the new board

    assert_not Current.user.admin?
    assert Current.user.can_administer_board?(board) # authorized through the creator path, not the admin role
    assert_includes card.assignees, assignee
    assert_not board.accessible_to?(assignee)

    card.update!(board: board)
    assert_includes board.users.reload, assignee
  end

  test "a member with mere board access does not grant assignees access when moving the card" do
    Current.session = sessions(:david) # plain member: not an admin and not the private board's creator
    board = boards(:private)
    board.accesses.grant_to(users(:david)) # david holds mere access to the private board, not administration rights
    card = cards(:logo)
    assignee = users(:jz) # already assigned to the card via fixtures, no access to the private board

    assert board.accessible_to?(users(:david))
    assert_not Current.user.can_administer_board?(board)
    assert_includes card.assignees, assignee
    assert_not board.accessible_to?(assignee)

    card.update!(board: board)

    assert_not_includes board.users.reload, assignee,
      "a member with mere board access must not grant others access to a private board via a card move"
  end

  test "move cards to a different board" do
    card = cards(:logo)
    old_board = card.board
    new_board = boards(:private)

    card.comments.create!(body: "Sensitive information", creator: users(:david))

    card_events_on_old_board = card.events.where(board: old_board)
    comment_events_on_old_board = Event.where(board: old_board, eventable: card.comments)

    assert card_events_on_old_board.exists?
    assert comment_events_on_old_board.exists?

    card.move_to(new_board)

    assert_equal new_board, card.reload.board

    card_events_on_new_board = card.events.where(board: new_board)
    comment_events_on_new_board = Event.where(board: new_board, eventable: card.comments)

    assert_empty card_events_on_old_board
    assert_empty comment_events_on_old_board
    assert card_events_on_new_board.exists?
    assert comment_events_on_new_board.exists?
    assert card_events_on_new_board.find_by(action: "card_board_changed")
  end

  test "moving an epic carries its children along to the new board" do
    epic = cards(:redesign_epic)
    first_child = cards(:redesign_header)
    second_child = epic.board.cards.create!(title: "Update the footer", creator: users(:david), status: "published", parent: epic)
    new_board = boards(:private)

    epic.move_to(new_board)

    assert_equal new_board, epic.reload.board
    assert_equal new_board, first_child.reload.board
    assert_equal new_board, second_child.reload.board

    assert_equal epic, first_child.parent
    assert_equal epic, second_child.parent

    assert epic.valid?
    assert first_child.valid?
    assert second_child.valid?

    assert_equal [ first_child.number, second_child.number ].uniq.size, 2
    assert_not_equal epic.number, first_child.number
    assert_not_equal epic.number, second_child.number
  end

  test "moving a lone child to another board promotes it to top-level" do
    epic = cards(:redesign_epic)
    child = cards(:redesign_header)
    new_board = boards(:private)

    child.move_to(new_board)

    assert_equal new_board, child.reload.board
    assert_nil child.parent_id
    assert child.valid?

    assert_equal boards(:redesign_board), epic.reload.board
    assert_empty epic.children.reload
  end

  test "moving a lone child leaves its former parent and other siblings untouched" do
    epic = cards(:redesign_epic)
    moved_child = cards(:redesign_header)
    staying_child = epic.board.cards.create!(title: "Update the footer", creator: users(:david), status: "published", parent: epic)
    new_board = boards(:private)

    moved_child.move_to(new_board)

    assert_equal boards(:redesign_board), epic.reload.board
    assert_equal boards(:redesign_board), staying_child.reload.board
    assert_equal epic, staying_child.parent
  end

  test "moving a childless top-level card is unaffected by the hierarchy carry-along" do
    card = cards(:logo)
    new_board = boards(:private)

    assert_not card.child?
    assert_not card.epic?

    card.move_to(new_board)

    assert_equal new_board, card.reload.board
    assert_nil card.parent_id
  end

  test "moving an epic rolls back entirely if carrying a child fails" do
    epic = cards(:redesign_epic)
    first_child = cards(:redesign_header)
    second_child = epic.board.cards.create!(title: "Update the footer", creator: users(:david), status: "published", parent: epic)
    old_board = epic.board
    new_board = boards(:private)

    # RuntimeError, not ActiveRecord::Rollback: nested (non-requires_new) blocks swallow Rollback without unwinding.
    Card.any_instance.stubs(:track_board_change_event).returns(nil).then.raises(RuntimeError, "boom")

    assert_no_difference -> { Card.where(board: new_board).count } do
      assert_raises RuntimeError do
        epic.move_to(new_board)
      end
    end

    assert_equal old_board, epic.reload.board
    assert_equal old_board, first_child.reload.board
    assert_equal old_board, second_child.reload.board
  end

  test "a card is filled if it has either the title or the description set" do
    assert Card.new(title: "Some title").filled?
    assert Card.new(description: "Some description").filled?

    assert_not Card.new.filled?
  end

  test "pins are deleted when card moves to a board user cannot access" do
    card = cards(:logo)
    kevin = users(:kevin)
    david = users(:david)

    # David pins the card (Kevin already has it pinned via fixture)
    card.pin_by(david)

    assert card.pinned_by?(kevin)
    assert card.pinned_by?(david)

    # Kevin has access to the private board, David does not
    assert boards(:private).accessible_to?(kevin)
    assert_not boards(:private).accessible_to?(david)

    perform_enqueued_jobs only: Card::CleanInaccessibleDataJob do
      card.move_to(boards(:private))
    end

    assert card.pinned_by?(kevin), "Kevin's pin should remain (has board access)"
    assert_not card.pinned_by?(david), "David's pin should be deleted (no board access)"
  end

  test "watches are deleted when card moves to a board user cannot access" do
    card = cards(:logo)
    kevin = users(:kevin)
    david = users(:david)

    # Both watch the card via fixtures
    assert card.watched_by?(kevin)
    assert card.watched_by?(david)

    # Kevin has access to the private board, David does not
    assert boards(:private).accessible_to?(kevin)
    assert_not boards(:private).accessible_to?(david)

    perform_enqueued_jobs only: Card::CleanInaccessibleDataJob do
      card.move_to(boards(:private))
    end

    assert card.watched_by?(kevin), "Kevin's watch should remain (has board access)"
    assert_not card.watched_by?(david), "David's watch should be deleted (no board access)"
  end

  test "card has reactions association" do
    card = cards(:logo)
    user = users(:david)

    assert_difference "card.reactions.count", +1 do
      card.reactions.create!(content: "👍", reacter: user)
    end

    reaction = card.reactions.last
    assert_equal "👍", reaction.content
    assert_equal user, reaction.reacter
    assert_equal card, reaction.reactable
  end
end
