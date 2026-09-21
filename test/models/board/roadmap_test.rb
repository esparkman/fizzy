require "test_helper"

class Board::RoadmapTest < ActiveSupport::TestCase
  setup do
    Current.session = sessions(:david)
    @board = boards(:writebook)
  end

  test "an epic tagged phase:p1 lands in the P1 group as an epic" do
    card = publish_card title: "Ship the redesign"
    card.toggle_tag_with "phase:p1"
    card.toggle_tag_with "type:epic"

    group = phase_group("p1")

    assert_equal "P1", group.title
    assert_includes group.epics.map(&:card), card
  end

  test "bare p2 and epic tags are recognized the same as their namespaced form" do
    card = publish_card title: "Bare tag epic"
    card.toggle_tag_with "p2"
    card.toggle_tag_with "epic"

    group = phase_group("p2")

    assert_equal "P2", group.title
    assert_includes group.epics.map(&:card), card
  end

  test "phases are ordered numerically, non-numbered phases sort after, and Unphased always sorts last" do
    p10_card = publish_card(title: "Far future")
    p10_card.toggle_tag_with "phase:p10"

    p0_card = publish_card(title: "Right now")
    p0_card.toggle_tag_with "phase:p0"

    beta_card = publish_card(title: "Named phase")
    beta_card.toggle_tag_with "phase:beta"

    unphased_card = publish_card(title: "No phase tag at all")

    labels = roadmap.phase_groups.map(&:label)

    assert_equal %w[ p0 p10 beta unphased ], labels
    assert_includes phase_group("unphased").cards.map(&:card), unphased_card
  end

  test "closed card is reported as shipped" do
    card = publish_card(title: "Done deal")
    card.close

    assert_equal :shipped, status_of(card)
  end

  test "postponed card is reported as not_now" do
    card = publish_card(title: "Later maybe")
    card.postpone

    assert_equal :not_now, status_of(card)
  end

  test "triaged open card is reported as in_flight" do
    card = publish_card(title: "Working on it", column: columns(:writebook_in_progress))

    assert_equal :in_flight, status_of(card)
  end

  test "untriaged published card is reported as planned" do
    card = publish_card(title: "Needs a column")

    assert_equal :planned, status_of(card)
  end

  test "stalled card is reported as stalled" do
    card = publish_card(title: "Gone quiet", column: columns(:writebook_in_progress))
    card.create_activity_spike!

    travel_to 3.months.from_now

    assert_equal :stalled, status_of(card)
  end

  test "step progress reports completed over total steps" do
    card = publish_card(title: "Has steps")
    card.steps.create!(content: "one", completed: true)
    card.steps.create!(content: "two", completed: true)
    card.steps.create!(content: "three", completed: false)

    roadmap_card = find_roadmap_card(card)

    assert_equal 2, roadmap_card.steps_completed
    assert_equal 3, roadmap_card.steps_total
  end

  test "a card with no steps reports 0 of 0" do
    card = publish_card(title: "No steps here")

    roadmap_card = find_roadmap_card(card)

    assert_equal 0, roadmap_card.steps_completed
    assert_equal 0, roadmap_card.steps_total
  end

  test "steps_percent is 0 for a card with no steps, avoiding a divide error" do
    card = publish_card(title: "No steps here")

    assert_equal 0, find_roadmap_card(card).steps_percent
  end

  test "steps_percent reports completed steps as a percent of total" do
    card = publish_card(title: "Partly done")
    card.steps.create!(content: "one", completed: true)
    card.steps.create!(content: "two", completed: true)
    card.steps.create!(content: "three", completed: true)
    card.steps.create!(content: "four", completed: false)
    card.steps.create!(content: "five", completed: false)

    assert_equal 60, find_roadmap_card(card).steps_percent
  end

  test "steps_percent is 100 when every step is completed" do
    card = publish_card(title: "All done")
    card.steps.create!(content: "one", completed: true)
    card.steps.create!(content: "two", completed: true)

    assert_equal 100, find_roadmap_card(card).steps_percent
  end

  test "board rollups tally shipped epics, in-flight cards, and deferred cards" do
    board = Board.create!(name: "Rollups", creator: users(:david), account: accounts(:"37s"))
    column = board.columns.create!(name: "In progress")

    shipped_epic = board.cards.create!(title: "Shipped epic", creator: users(:david), status: "published")
    shipped_epic.toggle_tag_with "type:epic"
    shipped_epic.close

    board.cards.create!(title: "In flight", creator: users(:david), status: "published", column: column)

    not_now_card = board.cards.create!(title: "Not now", creator: users(:david), status: "published")
    not_now_card.postpone

    board.cards.create!(title: "Planned", creator: users(:david), status: "published")

    summary = Board::Roadmap.new(board).summary

    assert_equal 1, summary.total_epics
    assert_equal 1, summary.epics_shipped
    assert_equal 1, summary.in_flight
    assert_equal 1, summary.deferred
    assert_equal 1, summary.planned
    assert_equal 4, summary.total_cards
    assert_equal 1, summary.shipped
    assert_equal 0, summary.stalled
  end

  test "summary.shipped counts all shipped cards, not just shipped epics" do
    board = Board.create!(name: "Shipped tally", creator: users(:david), account: accounts(:"37s"))

    shipped_epic = board.cards.create!(title: "Shipped epic", creator: users(:david), status: "published")
    shipped_epic.toggle_tag_with "type:epic"
    shipped_epic.close

    shipped_story = board.cards.create!(title: "Shipped story", creator: users(:david), status: "published")
    shipped_story.close

    summary = Board::Roadmap.new(board).summary

    assert_equal 1, summary.epics_shipped
    assert_equal 2, summary.shipped
    assert_operator summary.shipped, :>, summary.epics_shipped
  end

  test "summary.completion_percent truncates rather than rounds" do
    board = Board.create!(name: "Completion percent", creator: users(:david), account: accounts(:"37s"))

    shipped_card = board.cards.create!(title: "Shipped", creator: users(:david), status: "published")
    shipped_card.close

    board.cards.create!(title: "Planned one", creator: users(:david), status: "published")
    board.cards.create!(title: "Planned two", creator: users(:david), status: "published")

    summary = Board::Roadmap.new(board).summary

    assert_equal 3, summary.total_cards
    assert_equal 1, summary.shipped
    assert_equal 33, summary.completion_percent
  end

  test "summary.stalled counts stalled cards" do
    board = Board.create!(name: "Stalled tally", creator: users(:david), account: accounts(:"37s"))
    column = board.columns.create!(name: "In progress")

    stalled_card = board.cards.create!(title: "Gone quiet", creator: users(:david), status: "published", column: column)
    stalled_card.create_activity_spike!

    travel_to 3.months.from_now

    summary = Board::Roadmap.new(board).summary

    assert_equal 1, summary.stalled
  end

  test "a card tagged with several phases is grouped under the lowest one, deterministically" do
    card = publish_card(title: "Multi-phase card")
    card.toggle_tag_with "phase:p3"
    card.toggle_tag_with "phase:p1"
    card.toggle_tag_with "phase:p2"

    p1_group = phase_group("p1")

    assert_includes p1_group.cards.map(&:card) + p1_group.epics.map(&:card), card
    assert_nil phase_group("p2")
    assert_nil phase_group("p3")
  end

  test "a card tagged domain:billing reports that domain" do
    card = publish_card(title: "Billing card")
    card.toggle_tag_with "domain:billing"

    assert_equal [ "billing" ], find_roadmap_card(card).domains
  end

  test "a card tagged with two domains reports both" do
    card = publish_card(title: "Multi-domain card")
    card.toggle_tag_with "domain:billing"
    card.toggle_tag_with "domain:payments"

    assert_equal %w[ billing payments ], find_roadmap_card(card).domains.sort
  end

  test "a bare tag without the domain: namespace is not recognized as a domain" do
    card = publish_card(title: "Bare domain-looking tag")
    card.toggle_tag_with "billing"

    assert_empty find_roadmap_card(card).domains
  end

  test "a type:story card lands among group.cards, not group.epics" do
    card = publish_card(title: "Namespaced story")
    card.toggle_tag_with "phase:p5"
    card.toggle_tag_with "type:story"

    group = phase_group("p5")

    assert_includes group.cards.map(&:card), card
    assert_not_includes group.epics.map(&:card), card
  end

  test "a bare story tag lands among group.cards, not group.epics" do
    card = publish_card(title: "Bare story")
    card.toggle_tag_with "phase:p5"
    card.toggle_tag_with "story"

    group = phase_group("p5")

    assert_includes group.cards.map(&:card), card
    assert_not_includes group.epics.map(&:card), card
  end

  test "an epic's children are nested under it, not listed as top-level rows" do
    epic = publish_card(title: "Epic with children")
    epic.toggle_tag_with "phase:p8"

    child_one = publish_child(title: "Child one", parent: epic)
    child_two = publish_child(title: "Child two", parent: epic)

    group = phase_group("p8")
    epic_card = group.epics.find { |roadmap_card| roadmap_card.card == epic }

    assert_equal [ child_one, child_two ], epic_card.children.map(&:card)
    assert_not_includes group.cards.map(&:card), child_one
    assert_not_includes group.cards.map(&:card), child_two
    assert_not_includes group.epics.map(&:card), child_one
  end

  test "a child inherits its parent's phase even when the child has its own conflicting phase tag" do
    epic = publish_card(title: "Phase-owning epic")
    epic.toggle_tag_with "phase:p9"

    child = publish_child(title: "Mistagged child", parent: epic)
    child.toggle_tag_with "phase:p1"

    p9_group = phase_group("p9")
    epic_card = p9_group.epics.find { |roadmap_card| roadmap_card.card == epic }

    assert_includes epic_card.children.map(&:card), child
    assert_nil phase_group("p1")
  end

  test "a child whose epic is unphased nests under the epic in the Unphased group" do
    epic = publish_card(title: "Unphased epic")
    child = publish_child(title: "Unphased child", parent: epic)

    epic_card = phase_group("unphased").epics.find { |roadmap_card| roadmap_card.card == epic }

    assert_includes epic_card.children.map(&:card), child
  end

  test "an epic's child_rollup and aggregated steps reflect its children" do
    epic = publish_card(title: "Epic with progress")
    epic.steps.create!(content: "epic step", completed: true)

    shipped_child = publish_child(title: "Shipped child", parent: epic)
    shipped_child.steps.create!(content: "one", completed: true)
    shipped_child.steps.create!(content: "two", completed: false)
    shipped_child.close

    planned_child = publish_child(title: "Planned child", parent: epic)
    planned_child.steps.create!(content: "one", completed: true)

    epic_card = find_roadmap_card(epic)

    assert_equal 1, epic_card.child_rollup.shipped
    assert_equal 1, epic_card.child_rollup.planned
    assert_equal 2, epic_card.child_rollup.total
    assert_equal 3, epic_card.steps_completed
    assert_equal 4, epic_card.steps_total
  end

  test "a childless card reports a nil child_rollup" do
    card = publish_card(title: "No children here")

    assert_nil find_roadmap_card(card).child_rollup
  end

  test "a structurally-detected epic (has children, no epic tag) is treated as an epic" do
    epic = publish_card(title: "Untagged epic")
    publish_child(title: "Its only child", parent: epic)

    epic_card = find_roadmap_card(epic)

    assert_equal :epic, epic_card.type
  end

  test "summary counts children toward total_epics, and structural epics count even when untagged" do
    board = Board.create!(name: "Structural epics", creator: users(:david), account: accounts(:"37s"))

    epic = board.cards.create!(title: "Structural epic", creator: users(:david), status: "published")
    board.cards.create!(title: "Its child", creator: users(:david), status: "published", parent: epic)

    summary = Board::Roadmap.new(board).summary

    assert_equal 1, summary.total_epics
    assert_equal 2, summary.total_cards
  end

  test "summary totals count nested children the same as it would flat cards" do
    board = Board.create!(name: "Nested vs flat", creator: users(:david), account: accounts(:"37s"))

    epic = board.cards.create!(title: "Epic", creator: users(:david), status: "published")
    epic.toggle_tag_with "type:epic"
    epic.close

    child = board.cards.create!(title: "Child", creator: users(:david), status: "published", parent: epic)
    child.postpone

    flat_board = Board.create!(name: "Flat comparison", creator: users(:david), account: accounts(:"37s"))
    flat_epic = flat_board.cards.create!(title: "Epic", creator: users(:david), status: "published")
    flat_epic.toggle_tag_with "type:epic"
    flat_epic.close
    flat_story = flat_board.cards.create!(title: "Child", creator: users(:david), status: "published")
    flat_story.postpone

    nested_summary = Board::Roadmap.new(board).summary
    flat_summary = Board::Roadmap.new(flat_board).summary

    assert_equal flat_summary.total_cards, nested_summary.total_cards
    assert_equal flat_summary.shipped, nested_summary.shipped
    assert_equal flat_summary.deferred, nested_summary.deferred
  end

  test "a published child whose parent isn't published renders top-level and counts in the summary" do
    board = Board.create!(name: "Orphaned child", creator: users(:david), account: accounts(:"37s"))

    drafted_parent = board.cards.create!(title: "Drafted parent", creator: users(:david), status: "drafted")
    orphan = board.cards.create!(title: "Orphaned child", creator: users(:david), status: "published", parent: drafted_parent)
    orphan.close

    roadmap = Board::Roadmap.new(board)

    assert_includes roadmap.phase_groups.flat_map(&:all_cards).map(&:card), orphan
    assert_equal 1, roadmap.summary.total_cards
    assert_equal 1, roadmap.summary.shipped
  end

  test "nesting children under their epic issues no queries beyond the initial cards load" do
    epic = publish_card(title: "Query guarded epic")
    epic.toggle_tag_with "phase:p11"

    child_one = publish_child(title: "Guarded child one", parent: epic)
    child_one.close
    child_two = publish_child(title: "Guarded child two", parent: epic, column: columns(:writebook_in_progress))

    roadmap = Board::Roadmap.new(@board)
    roadmap.phase_groups # warm the single preloaded query build_phase_groups relies on

    assert_no_queries do
      roadmap.phase_groups
      roadmap.summary
    end
  end

  test "a card with no type tag defaults to a story" do
    card = publish_card(title: "Untyped card")

    assert_equal :story, find_roadmap_card(card).type
  end

  test "a card tagged as both epic and story resolves to epic" do
    card = publish_card(title: "Both typed")
    card.toggle_tag_with "type:epic"
    card.toggle_tag_with "type:story"

    assert_equal :epic, find_roadmap_card(card).type
  end

  test "a phase group partitions its epics and stories separately" do
    epic = publish_card(title: "Phase epic")
    epic.toggle_tag_with "phase:p6"
    epic.toggle_tag_with "type:epic"

    story = publish_card(title: "Phase story")
    story.toggle_tag_with "phase:p6"

    group = phase_group("p6")

    assert_equal [ epic ], group.epics.map(&:card)
    assert_equal [ story ], group.cards.map(&:card)
  end

  test "a phase's rollup tallies shipped, stalled, in_flight, and planned cards independently" do
    shipped = publish_card(title: "Shipped in phase")
    shipped.toggle_tag_with "phase:p4"
    shipped.close

    stalled = publish_card(title: "Stalled in phase", column: columns(:writebook_in_progress))
    stalled.toggle_tag_with "phase:p4"
    stalled.create_activity_spike!

    travel_to 3.months.from_now

    in_flight = publish_card(title: "In flight in phase", column: columns(:writebook_in_progress))
    in_flight.toggle_tag_with "phase:p4"

    planned = publish_card(title: "Planned in phase")
    planned.toggle_tag_with "phase:p4"

    group = phase_group("p4")

    assert_equal 1, group.rollup.shipped
    assert_equal 1, group.rollup.stalled
    assert_equal 1, group.rollup.in_flight
    assert_equal 1, group.rollup.planned
    assert_equal 4, group.rollup.total
  end

  test "meter_segments skips zero-count statuses and orders the rest by STATUS_ORDER, percents summing to 100" do
    shipped = publish_card(title: "Shipped in phase")
    shipped.toggle_tag_with "phase:p4"
    shipped.close

    stalled = publish_card(title: "Stalled in phase", column: columns(:writebook_in_progress))
    stalled.toggle_tag_with "phase:p4"
    stalled.create_activity_spike!

    travel_to 3.months.from_now

    in_flight = publish_card(title: "In flight in phase", column: columns(:writebook_in_progress))
    in_flight.toggle_tag_with "phase:p4"

    planned = publish_card(title: "Planned in phase")
    planned.toggle_tag_with "phase:p4"

    group = phase_group("p4")
    segments = group.meter_segments

    assert_equal [ :shipped, :in_flight, :stalled, :planned ], segments.map { |segment| segment[:status] }
    assert_equal [ 1, 1, 1, 1 ], segments.map { |segment| segment[:count] }
    assert_in_delta 100.0, segments.sum { |segment| segment[:percent] }
  end

  test "meter_segments is empty for a phase with no cards" do
    publish_card(title: "Unrelated card")

    empty_group = Board::Roadmap::PhaseGroup.new(label: "empty", title: "Empty", epics: [], cards: [], rollup: Board::Roadmap::Rollup.new(shipped: 0, not_now: 0, stalled: 0, in_flight: 0, planned: 0))

    assert_equal [], empty_group.meter_segments
  end

  test "cards_by_status returns every status in STATUS_ORDER, with empty statuses as [], and cards under the right key" do
    shipped = publish_card(title: "Shipped in phase")
    shipped.toggle_tag_with "phase:p4"
    shipped.close

    planned = publish_card(title: "Planned in phase")
    planned.toggle_tag_with "phase:p4"

    group = phase_group("p4")
    by_status = group.cards_by_status

    assert_equal Board::Roadmap::STATUS_ORDER, by_status.keys
    assert_equal [ shipped ], by_status[:shipped].map(&:card)
    assert_equal [ planned ], by_status[:planned].map(&:card)
    assert_equal [], by_status[:in_flight]
    assert_equal [], by_status[:stalled]
    assert_equal [], by_status[:not_now]
  end

  test "dimmed? is true for not_now cards only" do
    shipped = publish_card(title: "Shipped")
    shipped.close

    not_now = publish_card(title: "Postponed")
    not_now.postpone

    stalled = publish_card(title: "Stalled", column: columns(:writebook_in_progress))
    stalled.create_activity_spike!
    travel_to 3.months.from_now

    in_flight = publish_card(title: "In flight", column: columns(:writebook_in_progress))
    planned = publish_card(title: "Planned")

    assert_not find_roadmap_card(shipped).dimmed?
    assert find_roadmap_card(not_now).dimmed?
    assert_not find_roadmap_card(stalled).dimmed?
    assert_not find_roadmap_card(in_flight).dimmed?
    assert_not find_roadmap_card(planned).dimmed?
  end

  test "ordered_cards lists epics before stories, each ordered shipped, in_flight, stalled, planned, not_now" do
    shipped_story = publish_card(title: "Shipped story")
    shipped_story.toggle_tag_with "phase:p7"
    shipped_story.close

    not_now_story = publish_card(title: "Not now story")
    not_now_story.toggle_tag_with "phase:p7"
    not_now_story.postpone

    planned_story = publish_card(title: "Planned story")
    planned_story.toggle_tag_with "phase:p7"

    stalled_epic = publish_card(title: "Stalled epic", column: columns(:writebook_in_progress))
    stalled_epic.toggle_tag_with "phase:p7"
    stalled_epic.toggle_tag_with "type:epic"
    stalled_epic.create_activity_spike!

    travel_to 3.months.from_now

    in_flight_epic = publish_card(title: "In flight epic", column: columns(:writebook_in_progress))
    in_flight_epic.toggle_tag_with "phase:p7"
    in_flight_epic.toggle_tag_with "type:epic"

    group = phase_group("p7")

    assert_equal [ in_flight_epic, stalled_epic ], group.ordered_cards.first(2).map(&:card)
    assert_equal [ shipped_story, planned_story, not_now_story ], group.ordered_cards.last(3).map(&:card)
  end

  test "an empty board reports no phase groups at all and an all-zero summary" do
    empty_board = Board.create!(name: "Empty", creator: users(:david), account: accounts(:"37s"))
    empty_roadmap = Board::Roadmap.new(empty_board)

    assert_equal [], empty_roadmap.phase_groups

    summary = empty_roadmap.summary

    assert_equal 0, summary.total_epics
    assert_equal 0, summary.epics_shipped
    assert_equal 0, summary.in_flight
    assert_equal 0, summary.deferred
    assert_equal 0, summary.planned
    assert_equal 0, summary.total_cards
    assert_equal 0, summary.shipped
    assert_equal 0, summary.stalled
    assert_equal 0, summary.completion_percent
  end

  test "closed wins over postponed when a card is somehow forced into both states" do
    card = publish_card(title: "Both states at once")
    card.create_closure!(user: users(:david))
    card.create_not_now!(user: users(:david))

    assert_equal :shipped, status_of(card)
  end

  test "a published card on a different board never appears in this board's roadmap" do
    other_board_card = boards(:private).cards.create!(title: "Wrong board card", creator: users(:kevin), status: "published")

    assert_nil find_roadmap_card(other_board_card)
  end

  private
    def publish_card(title:, column: nil)
      @board.cards.create!(title: title, creator: users(:david), status: "published", column: column)
    end

    def publish_child(title:, parent:, column: nil)
      @board.cards.create!(title: title, creator: users(:david), status: "published", column: column, parent: parent)
    end

    def roadmap
      Board::Roadmap.new(@board)
    end

    def phase_group(label)
      roadmap.phase_groups.find { |group| group.label == label }
    end

    def find_roadmap_card(card)
      roadmap.phase_groups.flat_map(&:cards).concat(roadmap.phase_groups.flat_map(&:epics)).find { |rc| rc.card == card }
    end

    def status_of(card)
      find_roadmap_card(card).status
    end
end
