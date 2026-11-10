class EntriesController < ApplicationController
  before_action :require_year
  before_action :set_entry, only: [:show, :edit, :update, :destroy]
  def index
    @entries = selected_year.entries.includes(:category).order(date: :desc, id: :desc)
    @entries = @entries.in_month(selected_year.year, params[:month].to_i) if params[:month].to_i.in?(1..12)
    @entries = @entries.where(category_id: params[:category_id]) if params[:category_id].present?
    @entries = @entries.where(kind: params[:kind]) if Entry::KINDS.key?(params[:kind])
    @entries = @entries.where(status: params[:status]) if Entry::STATUSES.key?(params[:status])
    @entries = @entries.where('description LIKE ?', "%#{Entry.sanitize_sql_like(params[:q])}%") if params[:q].present?
    @count = @entries.count
    @page = [params[:page].to_i, 1].max
    @entries = @entries.limit(50).offset((@page - 1) * 50)
  end
  def new
    @entry = selected_year.entries.new(date: Date.new(selected_year.year, selected_month, [Date.current.day, Date.new(selected_year.year, selected_month, -1).day].min), kind: 'expense', status: 'planned')
  end
  def show; end
  def edit; end
  def create
    attrs = entry_params
    @entry = Entry.new(attrs)
    count = Integer(params[:installments].presence || 1)
    raise ArgumentError, 'Use entre 1 e 120 parcelas.' unless (1..120).cover?(count)
    Entry.transaction do
      if count > 1
        @entry = InstallmentBuilder.call(attrs, count: count).first
      else
        @entry.financial_year = YearBuilder.call(@entry.date.year) if @entry.date
        @entry.save!
      end
    end
    redirect_to entry_path(@entry), notice: count > 1 ? 'Parcelas planejadas e anos necessários criados.' : 'Lançamento criado.'
  rescue ActiveRecord::RecordInvalid, ArgumentError => e
    @entry ||= Entry.new
    @entry.errors.add(:base, e.message)
    render :new, status: :unprocessable_entity
  end
  def update
    attrs = entry_params
    Entry.transaction do
      @entry.assign_attributes(attrs)
      @entry.financial_year = YearBuilder.call(@entry.date.year) if @entry.date
      @entry.save!
    end
    redirect_to entry_path(@entry), notice: 'Lançamento atualizado.'
  rescue ActiveRecord::RecordInvalid, ArgumentError => e
    @entry.errors.add(:base, e.message)
    render :edit, status: :unprocessable_entity
  end
  def destroy
    @entry.destroy!
    redirect_to entries_path(year: @entry.financial_year.year), notice: 'Lançamento excluído.', status: :see_other
  end
  private
  def set_entry = @entry = Entry.find(params[:id])
  def entry_params
    attrs = params.require(:entry).permit(:date, :description, :category_id, :kind, :status, :amount, :payment_method, :notes).to_h
    attrs['amount'] = money_param(attrs['amount'])
    attrs
  end
end
