class CategoriesController < ApplicationController
  before_action :require_year
  before_action -> { @category = Category.find(params[:id]) }, only: [:edit, :update, :destroy]
  def index
    @categories = Category.order(:name)
    @report = BalanceReport.new(selected_year, status: selected_status, month: selected_month)
    @limits = selected_year.monthly_limits.where(month: selected_month).index_by(&:category_id)
  end
  def new = @category = Category.new
  def edit; end
  def create
    @category = Category.new(params.require(:category).permit(:name))
    save_with_limits(:new)
  end
  def update
    @category.assign_attributes(params.require(:category).permit(:name))
    save_with_limits(:edit)
  end
  def destroy
    if @category.destroy
      redirect_to categories_path, notice: 'Categoria excluída.', status: :see_other
    else
      redirect_to categories_path, alert: 'A categoria possui lançamentos ou contas fixas e não pode ser excluída.'
    end
  end
  private
  def save_with_limits(template)
    Category.transaction do
      @category.save!
      (1..12).each do |month|
        raw = params.fetch(:limits, {})[month.to_s]
        next if raw.blank?
        limit = selected_year.monthly_limits.find_or_initialize_by(category: @category, month: month)
        limit.update!(amount: money_param(raw))
      end
    end
    redirect_to categories_path, notice: 'Categoria e limites salvos.'
  rescue ActiveRecord::RecordInvalid, ArgumentError => e
    @category.errors.add(:base, e.message)
    render template, status: :unprocessable_entity
  end
end
