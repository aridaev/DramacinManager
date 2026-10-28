module DracinApi
  module Adapters
    # https://drakula.goodbos.online (host bersama) — auth ?code=KEY
    #   /api/microdrama/list?lang=&page=          → { data: { data: [ { id, title, cover, description, total_episodes } ] } }
    #   /api/microdrama/search?q=&lang=           → { data: { data: [...] } }
    #   /api/microdrama/drama/:id?lang=           → { data: { id, title, cover, description, total_episodes } } (tanpa daftar episode)
    #   /api/microdrama/play/:id/:ep?lang=        → { data: { videos: [ { quality: "720P", url } ] } }
    class Microdrama < Base
      default_host "https://drakula.goodbos.online"

      def home
        p1, p2 = concurrently(-> { list(1) }, -> { list(2) })
        [ section(I18n.t("template.v1.sections.latest"), p1), section(I18n.t("template.v1.sections.for_you"), p2) ]
      end

      def search(q, page: 1)
        items = Array(get("/api/microdrama/search", q: q, lang: lang).dig("data", "data")).map { |d| to_drama(d) }
        page(items, page: 1, has_more: false)
      end

      def detail(id) = to_drama((get("/api/microdrama/drama/#{id}", lang: lang)["data"] || {}).merge("id" => id))

      # API tidak memberi daftar episode; dibangun dari total_episodes.
      def episodes(id)
        total = detail(id).episodes.to_i
        (1..total).map { |n| episode(number: n, title: "EP #{n}", thumbnail: nil, duration: nil, locked: false, payload: {}) }
      end

      def play(id, ep)
        videos = Array(get("/api/microdrama/play/#{id}/#{ep}", lang: lang).dig("data", "videos")).select { |v| v["url"].present? }
        return nil if videos.empty?
        sorted = videos.sort_by { |v| -v["quality"].to_s.to_i }
        best = sorted.find { |v| v["quality"].to_s.to_i == 720 } || sorted.first
        stream(url: best["url"], episode: ep, sources: sorted.map { |v| { label: v["quality"].to_s.downcase, url: v["url"] } })
      end

      private
      def get(path, params = {})
        require_key!
        memo(path, params) { Http.get_json("#{host}#{path}", params: params.merge(code: api_key)) }
      end

      def list(page) = Array(get("/api/microdrama/list", lang: lang, page: page).dig("data", "data")).map { |d| to_drama(d) }

      def to_drama(d)
        drama(id: d["id"], title: d["title"].to_s.strip, cover: d["cover"], synopsis: d["description"], genres: Array(d["tags"]).first(5),
              episodes: d["total_episodes"].to_i.nonzero?, language: nil, rating: nil, year: nil, status: nil)
      end
    end
  end
end
