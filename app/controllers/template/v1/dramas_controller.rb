class Template::V1::DramasController < Template::V1::BaseController
  before_action :require_provider!
  before_action :load_drama

  def show; end

  def watch
    @episode_number = params[:ep].to_i
    @episode = @episodes.find { |e| e.number == @episode_number } || DracinApi::Catalog::Episode.new(number: @episode_number, locked: false)
    @stream = catalog.play(@drama.id, @episode_number) unless @episode.locked
    @play_url = play_url_for(@stream)
    @sources = sources_for(@stream)
    @subtitles = subtitles_for(@stream)
    @prev_episode = @episodes.select { |e| e.number < @episode_number }.max_by(&:number)
    @next_episode = @episodes.select { |e| e.number > @episode_number }.min_by(&:number)
  end

  private
  def load_drama
    @drama = catalog.detail(params[:id])
    @episodes = catalog.episodes(params[:id])
  end

  # Stream yang butuh cookie (signed CloudFront dsb.) diputar lewat proxy server.
  def play_url_for(stream)
    return nil if stream&.url.blank?
    return stream.url if stream.cookies.blank?
    template_v1_stream_path(Template::V1::StreamsController.register(stream), u: stream.url)
  end

  # Pilihan kualitas untuk pemutar; stream ber-cookie hanya punya satu sumber (lewat proxy).
  def sources_for(stream)
    return [] if stream.nil? || @play_url.blank?
    return [ { label: "Auto", url: @play_url } ] if stream.cookies.present?
    Array(stream.sources).presence || [ { label: "Auto", url: stream.url } ]
  end

  # Subtitle diputar lewat proxy same-origin (CORS + konversi SRT→VTT).
  def subtitles_for(stream)
    return [] if stream.nil?
    Array(stream.subtitles).select { |s| s[:url].present? }.map do |s|
      s.merge(src: template_v1_subtitle_path(t: Template::V1::SubtitlesController.token_for(s[:url])))
    end
  end
end
