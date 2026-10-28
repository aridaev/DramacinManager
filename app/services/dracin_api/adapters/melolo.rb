module DracinApi
  module Adapters
    # https://melolo.goodbos.online — token lewat query ?code=
    #   /api/home                 → { code, data: [ { id, name, cover, intro, episodes } ] }
    #   /api/search?q=            → { code, data: [...], has_more }
    #   /api/detail/:id           → { title, cover, intro, episodes, videos: [ { episode, vid, duration } ] }
    #   /api/video?id=&episode=   → { videoUrl, qualityList: [ { label, url } ], locked, totalEpisodes }
    class Melolo < Base
      default_host "https://melolo.goodbos.online"

      def home
        items = Array(get("/api/home")["data"]).map { |d| to_drama(d) }
        [ section(I18n.t("template.v1.sections.for_you"), items) ]
      end

      def search(q, page: 1)
        data = get("/api/search", q: q, page: page)
        page(Array(data["data"]).map { |d| to_drama(d) }, page: page, has_more: data["has_more"])
      end

      def detail(id)
        d = get("/api/detail/#{id}")
        drama(id: d["id"] || id, title: d["title"] || d["name"], cover: d["cover"], synopsis: d["intro"], episodes: d["episodes"].to_i.nonzero?,
              language: nil, rating: nil, year: nil, status: nil)
      end

      def episodes(id)
        Array(get("/api/detail/#{id}")["videos"]).map do |v|
          episode(number: v["episode"], title: "EP #{v['episode']}", thumbnail: nil, duration: seconds_to_clock(v["duration"]), locked: false, payload: v)
        end
      end

      def play(id, ep)
        v = get("/api/video", id: id, episode: ep)
        return nil if v["locked"] == true
        url = v["videoUrl"].presence || Array(v["qualityList"]).first&.dig("url")
        return nil if url.blank?
        sources = Array(v["qualityList"]).map { |q| { label: q["label"].to_s, url: q["url"] } }
        stream(url: url, episode: ep, sources: sources)
      end

      private
      def get(path, params = {})
        require_key!
        memo(path, params) { Http.get_json("#{host}#{path}", params: params.merge(code: api_key)) }
      end

      def to_drama(d)
        drama(id: d["id"], title: d["name"] || d["title"], cover: d["cover"], synopsis: d["intro"], episodes: d["episodes"].to_i.nonzero?,
              language: nil, rating: nil, year: nil, status: nil)
      end
    end
  end
end
