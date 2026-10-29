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

  # Stream ber-cookie (signed CloudFront) atau yang CDN-nya tanpa CORS/menolak Referer (proxied) diputar lewat proxy server.
  def play_url_for(stream)
    return nil if stream&.url.blank?
    @sid = Template::V1::StreamsController.register(stream) if stream.cookies.present? || stream.proxied
    proxied?(stream) ? template_v1_stream_path(@sid, u: stream.url) : stream.url
  end

  # Pilihan kualitas untuk pemutar; untuk stream proxied, setiap varian juga lewat proxy (sid yang sama).
  def sources_for(stream)
    return [] if stream.nil? || @play_url.blank?
    srcs = Array(stream.sources).presence || [ { label: "Auto", url: stream.url } ]
    return srcs unless proxied?(stream)
    # Varian MP4 tetap langsung (native <video> tidak butuh CORS); hanya HLS/ber-cookie yang lewat proxy.
    srcs.map { |s| proxied?(stream, s[:url]) ? { label: s[:label], url: template_v1_stream_path(@sid, u: s[:url]) } : s }
  end

  def proxied?(stream, url = stream.url)
    stream.cookies.present? || (stream.proxied && url.to_s.match?(%r{\.m3u8|/hls/}))
  end

  # Subtitle diputar lewat proxy same-origin (CORS + konversi SRT→VTT).
  def subtitles_for(stream)
    return [] if stream.nil?
    Array(stream.subtitles).select { |s| s[:url].present? }.map do |s|
      s.merge(src: template_v1_subtitle_path(t: Template::V1::SubtitlesController.token_for(s[:url])))
    end
  end
end
