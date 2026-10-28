# Kelola penonton (member) & pengajuan deposit per instance: approve/tolak, perpanjang, cabut bebas iklan.
# Akses mengikuti Admin::InstancesController (admin semua instance, user hanya miliknya).
class Admin::MembersController < ApplicationController
  layout "application"
  before_action :load_instance

  def index
    @pending  = @instance.deposit_requests.pending.includes(:member).order(created_at: :asc)
    @members  = @instance.members.ordered.includes(:deposit_requests)
    @recent   = @instance.deposit_requests.where.not(status: :pending).includes(:member).order(reviewed_at: :desc).limit(30)
  end

  def approve
    req = @instance.deposit_requests.pending.find(params[:id])
    req.approve!(params[:days])
    redirect_to admin_instance_members_path(@instance), notice: t("admin.members.approved", name: req.member.username, days: req.days)
  end

  def reject
    req = @instance.deposit_requests.pending.find(params[:id])
    req.reject!
    redirect_to admin_instance_members_path(@instance), notice: t("admin.members.rejected", name: req.member.username)
  end

  def grant
    m = @instance.members.find(params[:id])
    days = params[:days].to_i.clamp(1, 3650)
    m.grant_adfree!(days)
    redirect_to admin_instance_members_path(@instance), notice: t("admin.members.granted", name: m.username, days: days)
  end

  def revoke
    m = @instance.members.find(params[:id])
    m.revoke_adfree!
    redirect_to admin_instance_members_path(@instance), notice: t("admin.members.revoked", name: m.username)
  end

  def destroy
    m = @instance.members.find(params[:id])
    m.destroy
    redirect_to admin_instance_members_path(@instance), notice: t("admin.members.deleted", name: m.username)
  end

  private
  def load_instance
    scope = admin? ? Instance.all : Instance.where(created_by_id: current_user.id)
    @instance = scope.find(params[:instance_id])
  end
end
