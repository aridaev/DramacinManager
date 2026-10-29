module DracinApi
  module Adapters
    # https://drakula.goodbos.online (host bersama) — auth ?code=KEY
    #   /api/freereels/popular|foryou|new?lang=   → { data: { data: { items: [ { series: { key, title, cover, desc, episode_count, content_tags } } ] } } }
    #   /api/freereels/search?q=&lang=            → sama (q minimal 2 kata!)
    #   /api/freereels/drama/:key?lang=           → { data: { data: { info: { key, title, cover, desc, episode_count, content_tags }, episodes?: [...] } } }
    #   /api/freereels/drama/:key/play/:ep?lang=  → { data: { data: { episode_number, m3u8_url, external_audio_h264_m3u8, external_audio_h265_m3u8, cover } } }
    class Freereels < Base
      default_host "https://drakula.goodbos.online"

      def home
        popular, newest, foryou = concurrently(-> { list("popular") }, -> { list("new") }, -> { list("foryou") })
        [
          section(I18n.t("template.v1.sections.trending"), popular),
          section(I18n.t("template.v1.sections.latest"), newest),
          section(I18n.t("template.v1.sections.for_you"), foryou)
        ]
      end

      def search(q, page: 1)
        q = "#{q} drama" if q.to_s.split.size < 2 # API menolak kata kunci tunggal
        page(items_of(get("/api/freereels/search", q: q, lang: lang)), page: 1, has_more: false)
      end

      def detail(id)
        info = info_of(id)
        to_drama(info.merge("key" => info["key"] || id))
      end

      def episodes(id)
        data = get("/api/freereels/drama/#{id}", lang: lang).dig("data", "data") || {}
        list = Array(data["episodes"] || data["episode_list"] || data.dig("info", "episode_list"))
        if list.any?
          list.map { |e| n = (e["episode_number"] || e["number"] || e["index"]).to_i; episode(number: n, title: "EP #{n}", thumbnail: e["cover"], duration: nil, locked: false, payload: {}) }
        else
          total = (data.dig("info", "episode_count") || 0).to_i
          (1..total).map { |n| episode(number: n, title: "EP #{n}", thumbnail: nil, duration: nil, locked: false, payload: {}) }
        end
      end

      def play(id, ep)
        d = get("/api/freereels/drama/#{id}/play/#{ep}", lang: lang).dig("data", "data") || {}
        url = d["m3u8_url"].presence || d["external_audio_h264_m3u8"].presence || d["video_url"]
        return nil if url.blank?
        stream(url: url, episode: ep, proxied: true)
      end

      private
      def get(path, params = {})
        require_key!
        memo(path, params) { Http.get_json("#{host}#{path}", params: params.merge(code: api_key)) }
      end

      def items_of(json) = Array(json.dig("data", "data", "items")).map { |it| to_drama(it["series"] || it) }
      def list(kind) = items_of(get("/api/freereels/#{kind}", lang: lang))
      def info_of(id) = get("/api/freereels/drama/#{id}", lang: lang).dig("data", "data", "info") || {}

      def to_drama(d)
        drama(id: d["key"] || d["id"], title: (d["title"] || d["name"]).to_s.strip, cover: d["cover"], synopsis: d["desc"] || d["description"],
              genres: Array(d["content_tags"]).first(5), episodes: d["episode_count"].to_i.nonzero?, language: nil, rating: nil, year: nil, status: nil)
      end
    end
  end
end
