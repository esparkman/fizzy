class Cards::ParentsController < ApplicationController
  include CardScoped

  def update
    @card.update!(parent: find_candidate_parent)

    respond_to do |format|
      format.turbo_stream { render_parent_picker_replacement(@card.reload) }
      format.json { head :no_content }
    end
  rescue ActiveRecord::RecordNotFound
    @card.errors.add(:parent, "must be a top-level card on the same board")
    render_invalid_parent
  rescue ActiveRecord::RecordInvalid
    @card.restore_attributes([ :parent_id ])
    render_invalid_parent
  end

  def destroy
    @card.update!(parent: nil)

    respond_to do |format|
      format.turbo_stream { render_parent_picker_replacement(@card.reload) }
      format.json { head :no_content }
    end
  end

  private
    def find_candidate_parent
      @card.candidate_parents.find(params[:parent_id])
    end

    def render_invalid_parent
      respond_to do |format|
        format.turbo_stream { render_parent_picker_replacement(@card, status: :unprocessable_entity) }
        format.json { render json: { errors: @card.errors.full_messages }, status: :unprocessable_entity }
      end
    end

    def render_parent_picker_replacement(card, status: :ok)
      render turbo_stream: turbo_stream.replace([ card, :parent ], partial: "cards/parents/picker", method: "morph", locals: { card: card }), status: status
    end
end
