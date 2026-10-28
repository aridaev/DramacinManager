module DracinApi
  module Adapters
    # https://shortmax.goodbos.online — auth via query ?code=KEY (x-token ditolak "Invalid or expired code")
    #   /api/v1/popular?lang=&page=   /new   /hot        → { data: [ { id, code, name, cover, episodes, summary, tags } ] }
    #   /api/v1/search?q=&lang=                           → { data: [...] }
    #   /api/v1/detail/:id?lang=                          → { data: { id, name, cover, episodes, summary, tags } }
    #   /api/v1/alleps/:id?lang=                          → { data: { name, totalEpisodes, episodes: [ { episode, cover, duration, video: { video_480/720/1080 } } ] } }
    # Semua URL HLS ber-signature (expires_in ~8 jam); tidak ada flag lock.
    class Shortmax < Base
      default_host "https://shortmax.goodbos.online"
      QUALITY_KEYS = { "video_1080" => "1080p", "video_720" => "720p", "video_480" => "480p" }.freeze

      def home
        popular, newest, hot = concurrently(-> { list("/api/v1/popular") }, -> { list("/api/v1/new") }, -> { list("/api/v1/hot") })
        [
          section(I18n.t("template.v1.sections.trending"), popular),
          section(I18n.t("template.v1.sections.latest"), newest),
          section(I18n.t("template.v1.sections.for_you"), hot)
        ]
      end

      def search(q, page: 1)
        items = Array(get("/api/v1/search", q: q, lang: lang)["data"]).map { |d| to_drama(d) }
        page(items, page: 1, has_more: false)
      end

      def detail(id) = to_drama(get("/api/v1/detail/#{id}", lang: lang)["data"] || {}, id: id)

      def episodes(id)
        Array(alleps(id)["episodes"]).map do |ep|
          episode(number: ep["episode"], title: "EP #{ep['episode']}", thumbnail: ep["cover"], duration: seconds_to_clock(ep["duration"]),
                  locked: false, payload: ep["video"] || {})
        end
      end

      def play(id, ep)
        item = find_episode(id, ep) or return nil
        v = item.payload
        url = v["video_720"].presence || v["video_1080"].presence || v["video_480"]
        return nil if url.blank?
        stream(url: url, episode: ep, sources: sources_from(v, QUALITY_KEYS))
      end

      private
      def get(path, params = {})
        require_key!
        memo(path, params) { Http.get_json("#{host}#{path}", params: params.merge(code: api_key)) }
      end

      def list(path)
        Array(get(path, lang: lang, page: 1)["data"]).first(60).map { |d| to_drama(d) }
      end

      def alleps(id) = get("/api/v1/alleps/#{id}", lang: lang)["data"] || {}

      def to_drama(d, id: nil)
        drama(id: d["id"] || id, title: d["name"].to_s.strip, cover: d["cover"], synopsis: d["summary"], episodes: d["episodes"].to_i.nonzero?,
              genres: Array(d["tags"]).first(5), language: nil, rating: nil, year: nil, status: nil)
      end
    end
  end
end
