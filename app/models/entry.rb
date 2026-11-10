class Entry < ApplicationRecord
  include MonetaryPrecision
  KINDS = { 'income' => 'Entrada', 'expense' => 'Despesa', 'benefit_received' => 'Benefício recebido', 'benefit_used' => 'Benefício utilizado' }.freeze
  STATUSES = { 'planned' => 'Planejado', 'actual' => 'Realizado' }.freeze
  belongs_to :financial_year
  belongs_to :category
  belongs_to :recurring_rule, optional: true
  validates :date, :description, presence: true
  validates :description, length: { maximum: 250 }
  validates :amount, numericality: { greater_than: 0, less_than: 10**13 }
  validates :kind, inclusion: { in: KINDS.keys }
  validates :status, inclusion: { in: STATUSES.keys }
  validate :date_matches_year
  scope :in_month, ->(year, month) { where(date: Date.new(year, month).all_month) }
  scope :outgoing, -> { where(kind: %w[expense benefit_used]) }
  before_validation :set_completion_date
  after_commit :sync_google_calendar, on: [:create, :update]
  after_destroy_commit :remove_google_calendar_events

  private

  def set_completion_date
    if status == 'actual'
      if persisted? && status_change_to_be_saved == ['planned', 'actual']
        self.completed_on = Date.current
      else
        self.completed_on ||= date
      end
    else
      self.completed_on = nil
    end
  end

  def sync_google_calendar
    return if GoogleCalendarEntrySync.callbacks_suppressed?
    return unless kind == 'expense' || (saved_change_to_kind? && kind_before_last_save == 'expense')
    return unless User.where.not(google_calendar_id: nil).exists?

    GoogleCalendarEntrySync.call(id, transitioned_to_actual: saved_change_to_status? && status_before_last_save == 'planned' && status == 'actual')
  rescue StandardError => error
    Rails.logger.error("Google Calendar sync failed for entry #{id}: #{error.class}: #{error.message}")
    User.where.not(google_calendar_id: nil).update_all(google_calendar_sync_error: 'Não foi possível sincronizar um lançamento. Reconecte ou sincronize novamente nas Configurações.')
  end

  def remove_google_calendar_events
    return if GoogleCalendarEntrySync.callbacks_suppressed?
    return unless kind == 'expense'
    return unless User.where.not(google_calendar_id: nil).exists?

    GoogleCalendarEntrySync.remove(id)
  rescue StandardError => error
    Rails.logger.error("Google Calendar removal failed for entry #{id}: #{error.class}: #{error.message}")
  end

  def date_matches_year
    errors.add(:date, 'deve pertencer ao ano financeiro') if date && financial_year && date.year != financial_year.year
  end
end
