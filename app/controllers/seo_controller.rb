require "net/http"

# Endpoint SEO per host: /robots.txt, /sitemap.xml, /sitemap-<part>.xml, /<indexnow-key>.txt.
# Berlaku di host utama (prefix /template/vN) maupun domain instance (root).
class SeoController < ActionController::Base
  SITEMAP_TTL = 6.hours

  def robots
    inst = InstanceHost.resolve(request.env)
    lines = [ "User-agent: *", "Allow: /", "Disallow: /admin", "Disallow: /users", "Disallow: /covers", "Disallow: /provider_logos",
              "Disallow: /*/stream/", "Disallow: /*/subtitle", "Disallow: /*?preview_instance=", "" ]
    if inst
      lines << "Disallow: /akun"
      lines << "Sitemap: #{request.base_url}/sitemap.xml"
    else
      # Host utama hanya untuk admin/pratinjau template: jangan diindeks.
      lines = [ "User-agent: *", "Disallow: /", "" ]
    end
    render plain: lines.join("\n") + "\n", content_type: "text/plain"
  end

  def sitemap
    return head :not_found unless InstanceHost.resolve(request.env)
    xml = Rails.cache.fetch([ "sitemap", request.host, params[:tpl], params[:part].to_s, I18n.locale ], expires_in: SITEMAP_TTL) do
      builder = SitemapBuilder.new(base_url: request.base_url, prefix: prefix)
      params[:part].present? ? builder.part(params[:part]) : builder.index
    end
    return head :not_found if xml.nil?
    expires_in 1.hour, public: true
    render xml: xml
  end

  def indexnow_key
    inst = InstanceHost.resolve(request.env)
    return head :not_found unless inst&.indexnow_key.present? && params[:key] == inst.indexnow_key
    key = inst.indexnow_key
    render plain: key, content_type: "text/plain"
  end

  private
  def prefix
    return "" if InstanceHost.resolve(request.env)
    "/template/#{Instance::TEMPLATES.key?(params[:tpl]) ? params[:tpl] : 'v1'}"
  end
end
