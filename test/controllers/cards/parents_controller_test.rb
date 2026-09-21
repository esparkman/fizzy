require "test_helper"

class Cards::ParentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as :kevin
    @board = boards(:writebook)

    Current.set(session: sessions(:kevin)) do
      @epic = @board.cards.create!(title: "Ship redesign", creator: users(:kevin), status: "published")
      @story = @board.cards.create!(title: "Design new nav", creator: users(:kevin), status: "published")
    end
  end

  test "update assigns a valid parent" do
    assert_changes -> { @story.reload.parent }, from: nil, to: @epic do
      patch card_parent_path(@story), params: { parent_id: @epic.id }, as: :turbo_stream
    end

    assert_response :success
  end

  test "update rejects a parent on a different board with a visible error" do
    other_board_epic = Current.set(session: sessions(:kevin)) do
      boards(:private).cards.create!(title: "Private board epic", creator: users(:kevin), status: "published")
    end

    assert_no_changes -> { @story.reload.parent_id } do
      patch card_parent_path(@story), params: { parent_id: other_board_epic.id }, as: :turbo_stream
    end

    assert_response :unprocessable_entity
    assert_match "same board", @response.body
  end

  test "update rejects assigning a parent to a card that already has children, and re-renders the persisted parent, not the rejected one" do
    Current.set(session: sessions(:kevin)) do
      @epic.children.create!(board: @board, creator: users(:kevin), status: "published", title: "Nested story")
    end

    assert_no_changes -> { @epic.reload.parent_id } do
      patch card_parent_path(@epic), params: { parent_id: @story.id }, as: :turbo_stream
    end

    assert_response :unprocessable_entity
    assert_match "already has children", @response.body
    # @epic has no persisted parent -- the picker must show "None", not @story
    # (the rejected candidate), even though @card.parent was assigned @story
    # in memory before the save was rolled back.
    assert_match "Parent epic: <strong>None</strong>", @response.body
    assert_no_match @story.title, @response.body
    assert_nil @epic.reload.parent_id
  end

  test "destroy clears the parent" do
    @story.update!(parent: @epic)

    assert_changes -> { @story.reload.parent }, from: @epic, to: nil do
      delete card_parent_path(@story), as: :turbo_stream
    end

    assert_response :success
  end

  test "a user without board access cannot reparent" do
    private_card, private_epic = Current.set(session: sessions(:kevin)) do
      [
        boards(:private).cards.create!(title: "A private board story", creator: users(:kevin), status: "published"),
        boards(:private).cards.create!(title: "A private board epic", creator: users(:kevin), status: "published")
      ]
    end

    logout_and_sign_in_as :david

    patch card_parent_path(private_card), params: { parent_id: private_epic.id }, as: :turbo_stream

    assert_response :not_found
    assert_nil private_card.reload.parent_id
  end
end
