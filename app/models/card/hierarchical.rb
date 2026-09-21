module Card::Hierarchical
  extend ActiveSupport::Concern

  included do
    belongs_to :parent, class_name: "Card", optional: true
    has_many :children, class_name: "Card", foreign_key: :parent_id, dependent: :nullify

    scope :top_level, -> { where(parent_id: nil) }

    validate :parent_cannot_be_self, if: :parent_id?
    validate :parent_cannot_have_a_parent, if: :parent_id?
    validate :cannot_have_children_when_assigned_a_parent, if: :parent_id?
    validate :parent_must_be_on_the_same_board, if: :parent_id?
    validate :parent_must_be_on_the_same_account, if: :parent_id?
  end

  def child?
    parent_id.present?
  end

  def epic?
    (children.loaded? ? children.any? : children.exists?) || epic_tagged?
  end

  def candidate_parents
    board.cards.published.top_level.where.not(id: id).order(:title)
  end

  def parentable?
    children.none?
  end

  private
    def parent_cannot_be_self
      if parent_id == id
        errors.add(:parent, "can't be the card itself")
      end
    end

    def parent_cannot_have_a_parent
      if parent&.parent_id.present?
        errors.add(:parent, "can't have a parent of its own")
      end
    end

    def cannot_have_children_when_assigned_a_parent
      if children.any?
        errors.add(:parent, "can't be assigned to a card that already has children")
      end
    end

    def parent_must_be_on_the_same_board
      if parent && parent.board_id != board_id
        errors.add(:parent, "must be on the same board")
      end
    end

    def parent_must_be_on_the_same_account
      if parent && parent.account_id != account_id
        errors.add(:parent, "must be on the same account")
      end
    end
end
