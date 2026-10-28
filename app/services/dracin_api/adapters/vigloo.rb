module DracinApi
  module Adapters
    # https://vigloo.goodbos.online — header x-token
    #   /api/home?lang=&page=        → { programs: [ { id, title, thumbnail|thumbnailExpanded|titleImage, synopsis, genres: [ { title } ], episodeCount, releaseDate } ], hasMore }
    #   /api/search?q=&lang=&page=   → { programs: [...], hasMore }
    #   /api/detail?id=&lang=        → { program: {...}, seasons: [ { id, episodeCount, episodes: [ { id, episodeNumber, duration, price } ] } ] }
    #   /api/play?seasonId=&ep=      → { payload: { url } }
    class Vigloo < Base
      default_host "https://vigloo.goodbos.online"

      def home
        data = get("/api/home", lang: lang)
        [ section(I18n.t("template.v1.sections.featured"), Array(data["programs"]).map { |d| to_drama(d) }) ]
      end

      def search(q, page: 1)
        data = get("/api/search", q: q, lang: lang, page: page)
        page(Array(data["programs"]).map { |d| to_drama(d) }, page: data["page"] || page, has_more: data["hasMore"])
      end

      def detail(id)
        data = detail_data(id)
        d = to_drama(data["program"] || {})
        d.id = id.to_s
        d.episodes ||= Array(data["seasons"]).sum { |s| s["episodeCount"].to_i }.nonzero?
        d
      end

      def episodes(id)
        Array(detail_data(id)["seasons"]).flat_map do |season|
          Array(season["episodes"]).map do |e|
            episode(number: e["episodeNumber"], title: "EP #{e['episodeNumber']}", thumbnail: nil, duration: seconds_to_clock(e["duration"]),
                    locked: false, payload: { "seasonId" => season["id"] })
          end
        end
      end

      def play(id, ep)
        item = find_episode(id, ep) or return nil
        data = get("/api/play", seasonId: item.payload["seasonId"], ep: ep, lang: lang)
        url = data.dig("payload", "url")
        return nil if url.blank?
        # Stream dilindungi signed cookie CloudFront → diputar lewat proxy server (lihat Template::V1::StreamsController).
        cookies = (data["cloudfront"] || {}).slice("CloudFront-Policy", "CloudFront-Signature", "CloudFront-Key-Pair-Id").presence
        stream(url: url, episode: ep, cookies: cookies)
      end

      private
      def detail_data(id) = get("/api/detail", id: id, lang: lang)

      def to_drama(d)
        cover = [ d["thumbnail"], d["thumbnailExpanded"], Array(d["thumbnails"]).first&.dig("url"), d["titleImage"], d["bannerImage"] ].find(&:present?)
        drama(id: d["id"], title: d["title"], cover: cover, synopsis: d["synopsis"].presence || d["description"].presence || d["logLine"],
              genres: Array(d["genres"]).map { |g| g["title"] }.first(5), episodes: d["episodeCount"].to_i.nonzero?,
              language: nil, rating: nil, year: d["releaseDate"].to_s[0, 4].presence&.to_i, status: nil)
      end
    end
  end
end
