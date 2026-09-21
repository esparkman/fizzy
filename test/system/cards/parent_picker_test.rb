require "application_system_test_case"

class Cards::ParentPickerTest < ApplicationSystemTestCase
  include ActionView::RecordIdentifier

  test "an operator picks a parent epic and the story then nests under it on the roadmap" do
    board = Board.create!(name: "Parent picker board", creator: users(:david), account: accounts(:"37s"))

    epic, story = Current.set(session: sessions(:david)) do
      epic = board.cards.create!(title: "Ship the redesign", creator: users(:david), status: "published")
      epic.toggle_tag_with "phase:p1"

      story = board.cards.create!(title: "Design the new nav", creator: users(:david), status: "published")
      story.toggle_tag_with "phase:p1"

      [ epic, story ]
    end

    sign_in_as(users(:david))
    visit card_url(story)

    within "##{dom_id(story, :parent)}" do
      assert_text "Parent epic: None"
      select "Ship the redesign", from: "Change parent epic"
    end

    assert_text "Parent epic: Ship the redesign", wait: 5

    visit board_roadmap_url(board)

    epic_row = "##{dom_id(epic, :roadmap)}"

    within epic_row do
      assert_text "Ship the redesign"

      within "##{dom_id(epic, :roadmap)}_children" do
        assert_text "Design the new nav"
      end
    end
  end

  test "an operator removes a parent and the story returns to top-level" do
    board = Board.create!(name: "Clear parent board", creator: users(:david), account: accounts(:"37s"))

    epic, story = Current.set(session: sessions(:david)) do
      epic = board.cards.create!(title: "Ship the redesign", creator: users(:david), status: "published")
      epic.toggle_tag_with "phase:p1"

      story = board.cards.create!(title: "Design the new nav", creator: users(:david), status: "published", parent: epic)

      [ epic, story ]
    end

    sign_in_as(users(:david))
    visit card_url(story)

    within "##{dom_id(story, :parent)}" do
      assert_text "Parent epic: Ship the redesign"
      click_on "Clear parent epic"
    end

    assert_text "Parent epic: None", wait: 5

    visit board_roadmap_url(board)

    assert_no_selector "##{dom_id(epic, :roadmap)}_children", text: "Design the new nav"
    assert_selector ".roadmap__card", text: "Design the new nav"
  end
end
