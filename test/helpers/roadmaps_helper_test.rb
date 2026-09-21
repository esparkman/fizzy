require "test_helper"

class RoadmapsHelperTest < ActionView::TestCase
  test "roadmap_status_label humanizes each status" do
    assert_equal "Shipped", roadmap_status_label(:shipped)
    assert_equal "In flight", roadmap_status_label(:in_flight)
    assert_equal "Stalled", roadmap_status_label(:stalled)
    assert_equal "Planned", roadmap_status_label(:planned)
    assert_equal "Not now", roadmap_status_label(:not_now)
  end

  test "roadmap_status_icon returns the marker icon name for each status" do
    assert_equal "check-circle", roadmap_status_icon(:shipped)
    assert_equal "arrow-right", roadmap_status_icon(:in_flight)
    assert_equal "bell-alert", roadmap_status_icon(:stalled)
    assert_equal "minus", roadmap_status_icon(:planned)
    assert_equal "moon", roadmap_status_icon(:not_now)
  end

  test "roadmap_status_icon raises for an unexpected status" do
    assert_raises(KeyError) { roadmap_status_icon(:unknown) }
  end

  test "roadmap_status_modifier maps each status to its class suffix" do
    assert_equal "shipped", roadmap_status_modifier(:shipped)
    assert_equal "in-flight", roadmap_status_modifier(:in_flight)
    assert_equal "stalled", roadmap_status_modifier(:stalled)
    assert_equal "planned", roadmap_status_modifier(:planned)
    assert_equal "deferred", roadmap_status_modifier(:not_now)
  end

  test "roadmap_status_modifier raises for an unexpected status" do
    assert_raises(KeyError) { roadmap_status_modifier(:unknown) }
  end
end
