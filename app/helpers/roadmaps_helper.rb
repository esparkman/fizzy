module RoadmapsHelper
  STATUS_ICONS = {
    shipped: "check-circle",
    in_flight: "arrow-right",
    stalled: "bell-alert",
    planned: "minus",
    not_now: "moon"
  }.freeze

  STATUS_MODIFIERS = {
    shipped: "shipped",
    in_flight: "in-flight",
    stalled: "stalled",
    planned: "planned",
    not_now: "deferred"
  }.freeze

  def roadmap_status_label(status)
    status.to_s.humanize
  end

  def roadmap_status_icon(status)
    STATUS_ICONS.fetch(status)
  end

  # The bare modifier ("in-flight", "deferred", ...) shared by the marker,
  # meter segment, and status label classes for a given status.
  def roadmap_status_modifier(status)
    STATUS_MODIFIERS.fetch(status)
  end
end
