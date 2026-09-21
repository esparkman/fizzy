class Boards::RoadmapsController < ApplicationController
  include BoardScoped

  def show
    @roadmap = Board::Roadmap.new(@board)
    @view = params[:view].presence_in(%w[ list lanes ]) || Current.user.roadmap_view || "list"
  end
end
