require "test_helper"

class Boards::RoadmapsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as :kevin
  end

  test "a member of the board opens its roadmap and sees it" do
    board = boards(:writebook)

    # Current.session must be set because publishing tracks an event whose creator defaults to Current.user.
    card = Current.set(session: sessions(:kevin)) do
      board.cards.create!(title: "Ship the redesign", creator: users(:kevin), status: "published").tap do |card|
        card.toggle_tag_with "phase:p1"
      end
    end

    get board_roadmap_path(board)

    assert_response :success
    assert_select "h2", text: "P1"
    assert_select "li", text: /#{card.number}.*Ship the redesign/
  end

  test "a user without access cannot reach another board's roadmap" do
    logout_and_sign_in_as :david
    board = boards(:private)

    get board_roadmap_path(board)

    assert_response :not_found
  end

  test "renders the list view by default" do
    board = boards(:writebook)

    get board_roadmap_path(board)

    assert_response :success
    assert_select ".roadmap__phase"
    assert_select ".roadmap__lanes", false
  end

  test "renders the lanes view when the user's persisted preference is lanes" do
    board = boards(:writebook)
    users(:kevin).settings.update!(roadmap_view: "lanes")

    get board_roadmap_path(board)

    assert_response :success
    assert_select ".roadmap__lanes"
    assert_select ".roadmap__phase", false
  end

  test "a view param overrides the persisted list preference" do
    board = boards(:writebook)

    get board_roadmap_path(board, view: "lanes")

    assert_response :success
    assert_select ".roadmap__lanes"
  end

  test "a junk view param falls back to the persisted preference" do
    board = boards(:writebook)

    get board_roadmap_path(board, view: "grid")

    assert_response :success
    assert_select ".roadmap__phase"
    assert_select ".roadmap__lanes", false
  end

  test "renders the list view when the user has no settings row" do
    board = boards(:writebook)
    users(:kevin).settings.destroy
    users(:kevin).reload

    get board_roadmap_path(board)

    assert_response :success
    assert_select ".roadmap__phase"
    assert_select ".roadmap__lanes", false
  end

  test "a view param overrides a persisted lanes preference back to list" do
    board = boards(:writebook)
    users(:kevin).settings.update!(roadmap_view: "lanes")

    get board_roadmap_path(board, view: "list")

    assert_response :success
    assert_select ".roadmap__phase"
    assert_select ".roadmap__lanes", false
  end

  test "a junk view param falls back to a persisted lanes preference" do
    board = boards(:writebook)
    users(:kevin).settings.update!(roadmap_view: "lanes")

    get board_roadmap_path(board, view: "grid")

    assert_response :success
    assert_select ".roadmap__lanes"
    assert_select ".roadmap__phase", false
  end
end
