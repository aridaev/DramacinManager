module DracinApi
  module Adapters
    # https://drakula.goodbos.online (host bersama) — auth ?code=KEY
    #   /api/starshort/content/trending|hot|latest|recommended?lang=  → { data: [ { id, title, cover, tags, description?, episodes? } ] }
    #   /api/starshort/search?q=&lang=                               → { data: [ { id, title } ] }
    #   /api/starshort/show/:id?lang=                                → { data: { id, title, cover, description, tags, total_episodes? } }
    #   /api/starshort/show/:id/episodes?lang=                       → { data: { drama_id, episodes: [ { episode, free, price } ] } }
    #   /api/starshort/watch/:id/:ep?lang=                           → { data: { video_url (HLS, 47 jam), title } }
    class Starshort < Base
      default_host "https://drakula.goodbos.online"

      def home
        trending, latest, hot = concurrently(-> { list("trending") }, -> { list("latest") }, -> { list("hot") })
        [
          section(I18n.t("template.v1.sections.trending"), trending),
          section(I18n.t("template.v1.sections.latest"), latest),
          section(I18n.t("template.v1.sections.for_you"), hot)
        ]
      end

      def search(q, page: 1)
        items = Array(get("/api/starshort/search", q: q, lang: lang)["data"]).map { |d| to_drama(d) }
        page(items, page: 1, has_more: false)
      end

      def detail(id)
        d = get("/api/starshort/show/#{id}", lang: lang)["data"] || {}
        to_drama(d.merge("id" => d["id"] || id))
      end

      def episodes(id)
        Array(get("/api/starshort/show/#{id}/episodes", lang: lang).dig("data", "episodes")).map do |e|
          episode(number: e["episode"], title: "EP #{e['episode']}", thumbnail: nil, duration: nil, locked: false, payload: {})
        end
      end

      def play(id, ep)
        url = get("/api/starshort/watch/#{id}/#{ep}", lang: lang).dig("data", "video_url")
        return nil if url.blank?
        stream(url: url, episode: ep)
      end

      private
      def get(path, params = {})
        require_key!
        memo(path, params) { Http.get_json("#{host}#{path}", params: params.merge(code: api_key)) }
      end

      def list(kind) = Array(get("/api/starshort/content/#{kind}", lang: lang)["data"]).map { |d| to_drama(d) }

      def to_drama(d)
        drama(id: d["id"], title: d["title"].to_s.strip, cover: d["cover"], synopsis: d["description"] || d["desc"],
              genres: Array(d["tags"]).first(5), episodes: (d["total_episodes"] || d["episodes"] || d["episode_count"]).to_i.nonzero?,
              language: nil, rating: nil, year: nil, status: nil)
      end
    end
  end
end
