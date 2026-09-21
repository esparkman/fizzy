class My::RoadmapViewsController < ApplicationController
  def update
    board = Current.user.boards.find(params[:board_id])
    Current.user.settings.update!(roadmap_view: roadmap_view_param)
    redirect_to board_roadmap_path(board)
  rescue ActiveRecord::RecordInvalid
    head :unprocessable_entity
  end

  private
    def roadmap_view_param
      params[:roadmap_view]
    end
end
