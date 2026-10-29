module DracinApi
  module Adapters
    # https://vibeshort.goodbos.online (juga storyreel) — header x-token
    #   /api/v1/home?lang=            → { tabs, data: [ { id, code, name, cover, episodes, summary, tags } ] }
    #   /api/v1/search?q=&lang=       → { data: [...] }
    #   /api/v1/alleps/:id?lang=      → { data: { code, name, cover, summary, totalEpisodes, episodes: [ { episode, video: { video_720 }, cover, duration, locked } ] } }
    class Vibeshort < Base
      default_host "https://vibeshort.goodbos.online"

      def home
        data = get("/api/v1/home", lang: lang)
        items = Array(data["data"]).map { |d| to_drama(d) }
        title = Array(data["tabs"]).find { |t| t["id"] == data["tabId"] }&.dig("name")
        [ section(title.presence || I18n.t("template.v1.sections.for_you"), items.first(60)) ]
      end

      def search(q, page: 1)
        items = Array(get("/api/v1/search", q: q, lang: lang)["data"]).map { |d| to_drama(d) }
        page(items, page: 1, has_more: false)
      end

      def detail(id)
        d = alleps(id)
        drama(id: d["code"] || id, title: d["name"], cover: d["cover"], synopsis: d["summary"], episodes: d["totalEpisodes"].to_i.nonzero?,
              genres: Array(d["tags"]).first(5), language: nil, rating: nil, year: nil, status: nil)
      end

      def episodes(id)
        Array(alleps(id)["episodes"]).map do |ep|
          episode(number: ep["episode"], title: "EP #{ep['episode']}", thumbnail: ep["cover"], duration: seconds_to_clock(ep["duration"]),
                  locked: ep["locked"] == true, payload: ep["video"] || {})
        end
      end

      def play(id, ep)
        item = find_episode(id, ep) or return nil
        v = item.payload
        url = v["video_720"].presence || v["video_1080"].presence || v["video_480"]
        return nil if url.blank?
        stream(url: url, episode: ep, sources: sources_from(v, { "video_1080" => "1080p", "video_720" => "720p", "video_480" => "480p" }), proxied: true)
      end

      private
      def alleps(id) = get("/api/v1/alleps/#{id}", lang: lang)["data"] || {}

      def to_drama(d)
        drama(id: d["code"] || d["id"], title: d["name"], cover: d["cover"], synopsis: d["summary"], episodes: d["episodes"].to_i.nonzero?,
              genres: Array(d["tags"]).first(5), language: nil, rating: nil, year: nil, status: nil)
      end
    end
  end
end
