# Generate SEO via TokenPlus di latar belakang (Solid Queue). Status disimpan di settings instance
# (seo_job_status / seo_job_info / seo_job_at) dan dipantau halaman edit lewat seo_status.
class GenerateSeoJob < ApplicationJob
  queue_as :default
  discard_on ActiveJob::DeserializationError

  def perform(instance_id, locale)
    instance = Instance.find_by(id: instance_id)
    return unless instance
    I18n.with_locale(locale) do
      client = TokenPlusClient.from_settings
      raise SeoGenerator::Error, I18n.t("admin.instances.ai_not_configured") unless client.configured?
      SeoGenerator.new(instance, client: client, locale: locale).call
      instance.mark_seo_job!("ok", client.model)
    end
  rescue StandardError => e
    Rails.logger.error("[GenerateSeoJob] instance=#{instance_id} #{e.class}: #{e.message}")
    instance&.mark_seo_job!("failed", e.message.to_s.truncate(240))
  end
end
