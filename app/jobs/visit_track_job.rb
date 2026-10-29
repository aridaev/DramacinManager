class VisitTrackJob < ApplicationJob
  queue_as :default
  discard_on ActiveRecord::RecordNotFound, ActiveRecord::InvalidForeignKey, ActiveRecord::RecordInvalid

  def perform(attrs)
    Visit.create!(attrs.to_h.symbolize_keys)
  end
end
