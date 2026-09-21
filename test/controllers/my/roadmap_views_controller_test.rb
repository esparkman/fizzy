require "test_helper"

class My::RoadmapViewsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as :kevin
  end

  test "update persists the preference and redirects to the board's roadmap" do
    board = boards(:writebook)

    assert_not_equal "lanes", users(:kevin).roadmap_view

    patch my_roadmap_view_path, params: { roadmap_view: "lanes", board_id: board.id }

    assert_equal "lanes", users(:kevin).reload.roadmap_view
    assert_redirected_to board_roadmap_path(board)
  end

  test "a non-member board_id is not found" do
    logout_and_sign_in_as :david
    board = boards(:private)

    patch my_roadmap_view_path, params: { roadmap_view: "lanes", board_id: board.id }

    assert_response :not_found
    assert_not_equal "lanes", users(:david).roadmap_view
  end

  test "a junk roadmap_view value is rejected and the preference is unchanged" do
    board = boards(:writebook)

    patch my_roadmap_view_path, params: { roadmap_view: "grid", board_id: board.id }

    assert_response :unprocessable_entity
    assert_equal "list", users(:kevin).reload.roadmap_view
  end
end
