Rails.application.routes.draw do
  get 'up' => 'rails/health#show', as: :rails_health_check
  resource :session, only: [:new, :create, :destroy], path: 'acesso'
  root 'dashboard#show'
  get 'visao-anual', to: 'dashboard#annual', as: :annual
  resources :entries, path: 'lancamentos'
  resources :categories, path: 'categorias', except: :show
  resource :settings, path: 'configuracoes', only: [:show, :update]
  get 'configuracoes/google-calendar/conectar', to: 'google_calendar#connect', as: :connect_google_calendar
  get 'configuracoes/google-calendar/callback', to: 'google_calendar#callback', as: :google_calendar_callback
  delete 'configuracoes/google-calendar', to: 'google_calendar#disconnect', as: :disconnect_google_calendar
  post 'configuracoes/google-calendar/sincronizar', to: 'google_calendar#sync', as: :sync_google_calendar
  resources :financial_years, path: 'anos', only: :create
  resources :recurring_rules, path: 'contas-fixas', only: [:create, :destroy]
  resource :import, path: 'importacao', only: [:new, :create, :show, :destroy] do
    post :commit
  end
  resource :backup, only: [:show, :create] do
    post :restore
    delete :cancel
  end
end
