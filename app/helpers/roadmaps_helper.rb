module RoadmapsHelper
  RING_RADIUS = 42
  RING_STROKE_WIDTH = 8
  RING_CIRCUMFERENCE = (2 * Math::PI * RING_RADIUS).round(2)

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

  # An SVG progress ring for the roadmap hero, rotated so the arc starts at
  # the top. `percent` drives the stroke-dashoffset math off the fixed radius.
  def roadmap_progress_ring(percent)
    offset = (RING_CIRCUMFERENCE * (1 - percent / 100.0)).round(2)

    tag.svg class: "roadmap__ring-svg", viewBox: "0 0 96 96", "aria-hidden": true do
      tag.circle(class: "roadmap__ring-track", cx: 48, cy: 48, r: RING_RADIUS, fill: "none", "stroke-width": RING_STROKE_WIDTH) +
        tag.circle(class: "roadmap__ring-progress", cx: 48, cy: 48, r: RING_RADIUS, fill: "none", "stroke-width": RING_STROKE_WIDTH,
          "stroke-linecap": "round", "stroke-dasharray": RING_CIRCUMFERENCE, "stroke-dashoffset": offset)
    end
  end
end
