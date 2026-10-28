# Domain milik instance: tambah (→ provision zone Cloudflare), cek status NS, coba lagi, hapus.
class Admin::DomainsController < ApplicationController
  before_action :load_instance
  before_action :load_domain, only: [ :destroy, :refresh, :retry ]

  def create
    unless CloudflareClient.from_settings.configured? && Setting.vps_ip.present?
      return redirect_to admin_instance_path(@instance), alert: t("admin.domains.cf_not_ready")
    end
    domain = @instance.domains.new(hostname: params.dig(:domain, :hostname))
    return redirect_to admin_instance_path(@instance), alert: domain.errors.full_messages.join(", ") unless domain.save
    begin
      domain.provision!
      redirect_to admin_instance_path(@instance), notice: t("admin.domains.created", hostname: domain.hostname, ns: domain.nameservers.join(", "))
    rescue CloudflareClient::Error => e
      redirect_to admin_instance_path(@instance), alert: t("admin.domains.provision_failed", error: e.message)
    end
  end

  def refresh
    @domain.refresh_status!
    key = @domain.active? ? "admin.domains.now_active" : "admin.domains.still_pending"
    redirect_to admin_instance_path(@instance), notice: t(key, hostname: @domain.hostname, cf: @domain.cf_status)
  end

  def retry
    @domain.provision!
    redirect_to admin_instance_path(@instance), notice: t("admin.domains.retried", hostname: @domain.hostname)
  rescue CloudflareClient::Error => e
    redirect_to admin_instance_path(@instance), alert: t("admin.domains.provision_failed", error: e.message)
  end

  def destroy
    @domain.deprovision!(delete_zone: ActiveModel::Type::Boolean.new.cast(params[:delete_zone]))
    redirect_to admin_instance_path(@instance), notice: t("admin.domains.deleted", hostname: @domain.hostname)
  end

  private
  def load_instance
    scope = admin? ? Instance.all : Instance.where(created_by_id: current_user.id)
    @instance = scope.find(params[:instance_id])
  end

  def load_domain = @domain = @instance.domains.find(params[:id])
end
