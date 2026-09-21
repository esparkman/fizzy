require "test_helper"

class Card::HierarchicalTest < ActiveSupport::TestCase
  setup do
    Current.session = sessions(:david)
  end

  test "a card cannot be its own parent" do
    card = cards(:logo)
    card.parent = card

    assert_not card.valid?
    assert_includes card.errors[:parent], "can't be the card itself"
  end

  test "a card cannot be assigned to a parent that already has a parent" do
    child = cards(:layout)
    child.parent = cards(:redesign_header)

    assert_not child.valid?
    assert_includes child.errors[:parent], "can't have a parent of its own"
  end

  test "a card that already has children cannot be assigned a parent" do
    epic = cards(:redesign_epic)
    epic.parent = cards(:layout)

    assert_not epic.valid?
    assert_includes epic.errors[:parent], "can't be assigned to a card that already has children"
  end

  test "a parent must be on the same board" do
    card = cards(:private_board_card)
    card.parent = cards(:redesign_epic)

    assert_not card.valid?
    assert_includes card.errors[:parent], "must be on the same board"
  end

  test "a parent must be on the same account" do
    card = cards(:radio)
    card.parent = cards(:redesign_epic)

    assert_not card.valid?
    assert_includes card.errors[:parent], "must be on the same account"
  end

  test "top_level scope excludes children" do
    assert_includes Card.top_level, cards(:redesign_epic)
    assert_not_includes Card.top_level, cards(:redesign_header)
  end

  test "deleting an epic nullifies its children instead of destroying them" do
    epic = cards(:redesign_epic)
    child = cards(:redesign_header)

    assert_difference -> { Card.count }, -1 do
      epic.destroy
    end

    assert child.reload.persisted?
    assert_nil child.parent_id
  end

  test "a card with children is an epic" do
    assert cards(:redesign_epic).epic?
  end

  test "a childless card tagged as an epic is still an epic" do
    card = cards(:buy_domain)
    card.toggle_tag_with "type:epic"

    assert card.epic?
  end

  test "a card without children or the epic tag is not an epic" do
    assert_not cards(:buy_domain).epic?
  end

  test "only cards with a parent are children" do
    assert cards(:redesign_header).child?
    assert_not cards(:redesign_epic).child?
  end
end
