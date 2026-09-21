# Groups a board's published cards into an ordered set of phase groups, with
# each card's status rolled up from its native state (closure, not-now,
# activity spike, column) rather than from the column it happens to sit in.
#
# Only top-level cards occupy a phase group's rows; a card with children is
# an epic whose children are nested under it, grouped by the epic's own
# phase regardless of what phase tag a child might separately carry.
class Board::Roadmap
  STATUS_ORDER = %i[ shipped in_flight stalled planned not_now ].freeze

  RoadmapCard = Data.define(:card, :title, :number, :status, :type, :domains, :steps_completed, :steps_total, :children, :child_rollup) do
    def status_rank = STATUS_ORDER.index(status)

    def steps_percent
      return 0 if steps_total.zero?

      (steps_completed * 100 / steps_total)
    end

    def dimmed? = status == :not_now

    def self_and_descendants
      [ self ] + children.flat_map(&:self_and_descendants)
    end
  end

  PhaseGroup = Data.define(:label, :title, :epics, :cards, :rollup) do
    def all_cards
      epics + cards
    end

    def ordered_cards
      epics.sort_by(&:status_rank) + cards.sort_by(&:status_rank)
    end

    def meter_segments
      return [] if rollup.total.zero?

      STATUS_ORDER.filter_map do |status|
        count = rollup.public_send(status)
        next if count.zero?
        { status:, count:, percent: (count * 100.0 / rollup.total).round(1) }
      end
    end

    def cards_by_status
      grouped = all_cards.group_by(&:status)
      STATUS_ORDER.index_with { |status| grouped.fetch(status, []) }
    end
  end

  Rollup = Data.define(:shipped, :not_now, :stalled, :in_flight, :planned) do
    def total
      shipped + not_now + stalled + in_flight + planned
    end
  end

  Summary = Data.define(:total_epics, :epics_shipped, :in_flight, :deferred, :planned, :total_cards, :shipped, :stalled) do
    def completion_percent
      return 0 if total_cards.zero?

      (shipped * 100 / total_cards)
    end
  end

  PHASE_NAMESPACE_PATTERN = /\Aphase:(.+)\z/
  PHASE_BARE_PATTERN = /\Ap(\d+)\z/
  DOMAIN_NAMESPACE_PATTERN = /\Adomain:(.+)\z/
  UNPHASED_LABEL = "unphased"

  def initialize(board)
    @board = board
  end

  def phase_groups
    @phase_groups ||= build_phase_groups
  end

  def summary
    @summary ||= build_summary
  end

  private
    attr_reader :board

    def build_phase_groups
      top_level_cards = cards.select { |card| top_level?(card) }
      cards_by_phase_label = top_level_cards.group_by { |card| phase_label_for(card) }

      labels = (cards_by_phase_label.keys - [ UNPHASED_LABEL ]).sort_by { |label| phase_sort_key(label) }
      labels << UNPHASED_LABEL if cards_by_phase_label.key?(UNPHASED_LABEL)

      labels.map do |label|
        roadmap_cards = cards_by_phase_label[label].map { |card| roadmap_card_for(card) }
        epics, stories = roadmap_cards.partition { |roadmap_card| roadmap_card.type == :epic }

        PhaseGroup.new(
          label: label,
          title: phase_title_for(label),
          epics: epics,
          cards: stories,
          rollup: rollup_for(roadmap_cards)
        )
      end
    end

    def build_summary
      roadmap_cards = phase_groups.flat_map(&:all_cards).flat_map(&:self_and_descendants)
      epics = roadmap_cards.select { |roadmap_card| roadmap_card.type == :epic }
      counts = status_counts(roadmap_cards)

      Summary.new(
        total_epics: epics.size,
        epics_shipped: epics.count { |roadmap_card| roadmap_card.status == :shipped },
        in_flight: counts.fetch(:in_flight, 0),
        deferred: counts.fetch(:not_now, 0),
        planned: counts.fetch(:planned, 0),
        total_cards: roadmap_cards.size,
        shipped: counts.fetch(:shipped, 0),
        stalled: counts.fetch(:stalled, 0)
      )
    end

    def cards
      @cards ||= board.cards.published
        .preload(:tags, :closure, :not_now, :activity_spike, :column, :steps)
        .to_a
    end

    # Built once from the already-loaded `cards` array so nesting children
    # under their epic never issues a `children` association query per card.
    def children_by_parent_id
      @children_by_parent_id ||= cards.group_by(&:parent_id)
    end

    # A card is only nested under its parent when that parent is itself in
    # the loaded, published set. A published child whose parent is absent
    # (drafted, or otherwise outside `board.cards.published`) has nothing to
    # nest under, so it renders as its own top-level row instead of vanishing.
    def top_level?(card)
      card.parent_id.nil? || loaded_card_ids.exclude?(card.parent_id)
    end

    def loaded_card_ids
      @loaded_card_ids ||= cards.map(&:id).to_set
    end

    def roadmap_card_for(card)
      children = children_by_parent_id.fetch(card.id, []).map { |child| roadmap_card_for(child) }

      RoadmapCard.new(
        card: card,
        title: card.title,
        number: card.number,
        status: status_for(card),
        type: type_for(card, children),
        domains: domains_for(card),
        steps_completed: card.steps.count(&:completed?) + children.sum(&:steps_completed),
        steps_total: card.steps.size + children.sum(&:steps_total),
        children: children,
        child_rollup: children.any? ? rollup_for(children) : nil
      )
    end

    # Status is derived from the card's native state (closure, not-now,
    # stalled activity, having a column), never from the column it sits in.
    def status_for(card)
      if card.closed?
        :shipped
      elsif card.postponed?
        :not_now
      elsif card.stalled?
        :stalled
      elsif card.triaged?
        :in_flight
      else
        :planned
      end
    end

    def rollup_for(roadmap_cards)
      counts = status_counts(roadmap_cards)

      Rollup.new(
        shipped: counts.fetch(:shipped, 0),
        not_now: counts.fetch(:not_now, 0),
        stalled: counts.fetch(:stalled, 0),
        in_flight: counts.fetch(:in_flight, 0),
        planned: counts.fetch(:planned, 0)
      )
    end

    def status_counts(roadmap_cards)
      roadmap_cards.group_by(&:status).transform_values(&:size)
    end

    # Namespaced tag wins over its bare fallback; among several recognized
    # phase tags on one card, the lowest-ordered phase wins so grouping is
    # deterministic regardless of tagging order. A child's own phase tag is
    # never consulted here: children are nested under their epic's phase.
    def phase_label_for(card)
      labels = card.tags.filter_map { |tag| phase_label(tag.title) }
      labels.any? ? labels.min_by { |label| phase_sort_key(label) } : UNPHASED_LABEL
    end

    def phase_label(title)
      if (match = title.match(PHASE_NAMESPACE_PATTERN))
        match[1]
      elsif title.match?(PHASE_BARE_PATTERN)
        title
      end
    end

    def phase_sort_key(label)
      if (match = label.match(PHASE_BARE_PATTERN))
        [ 0, match[1].to_i, label ]
      else
        [ 1, 0, label ]
      end
    end

    def phase_title_for(label)
      if label == UNPHASED_LABEL
        "Unphased"
      elsif (match = label.match(PHASE_BARE_PATTERN))
        "P#{match[1]}"
      else
        label.titleize
      end
    end

    # A card is an epic structurally (it has children) or by tag; we check
    # the already-nested `children` array rather than `card.epic?` because
    # that predicate falls back to a `children.exists?` query per card.
    def type_for(card, children)
      children.any? || card.epic_tagged? ? :epic : :story
    end

    def domains_for(card)
      card.tags.filter_map { |tag| tag.title[DOMAIN_NAMESPACE_PATTERN, 1] }
    end
end
