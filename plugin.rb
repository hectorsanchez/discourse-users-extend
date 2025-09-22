# name: discourse-users-extend
# about: Plugin para mostrar usuarios de Discourse y agruparlos por país.
# version: 0.1
# authors: Héctor Sanchez

after_initialize do
  # Controlador simple sin Engine
  class ::DiscourseUsersController < ::ApplicationController
    skip_before_action :check_xhr, only: [:index, :users, :debug, :test]
    skip_before_action :redirect_to_login_if_required, only: [:index, :users, :debug, :test]
    
    def index
      # Página principal - renderizar HTML simple
      render html: '<div id="discourse-users-page"></div>'.html_safe, layout: 'application'
    end
    
    def users
      # Devolver datos reales de la API
      response.headers['Content-Type'] = 'application/json'
      response.headers['Access-Control-Allow-Origin'] = '*'
      
      api_key = SiteSetting.dmu_discourse_api_key
      api_username = SiteSetting.dmu_discourse_api_username
      discourse_url = SiteSetting.dmu_discourse_api_url
      
      if api_key.blank? || discourse_url.blank?
        render json: { error: "API Key y URL de Discourse no configurados correctamente." }, status: 400
        return
      end

      begin
        # Obtener lista de usuarios del directorio
        directory_url = "#{discourse_url}/directory_items.json?order=created&period=all&limit=10"
        directory_response = make_api_request(directory_url, api_key, api_username)
        
        if directory_response[:status_code] == 200
          directory_data = JSON.parse(directory_response[:body])
          users = directory_data['directory_items'].map { |item| item['user'] }
          
          # Procesar usuarios
          processed_users = users.map do |user|
            # Obtener perfil completo del usuario
            user_url = "#{discourse_url}/users/#{user['username']}.json"
            user_response = make_api_request(user_url, api_key, api_username)
            
            if user_response[:status_code] == 200
              user_data = JSON.parse(user_response[:body])['user']
              location = user_data['location']
              
              country = if location.present?
                if location.include?(',')
                  location.split(',').last.strip
                else
                  location
                end
              else
                "Sin país"
              end
              
              {
                firstname: user_data['name']&.split(' ')&.first || user_data['username'],
                lastname: user_data['name']&.split(' ')&.drop(1)&.join(' ') || '',
                email: user_data['email'],
                username: user_data['username'],
                location: location,
                country: country,
                trust_level: user_data['trust_level'],
                avatar_template: user_data['avatar_template']
              }
            else
              {
                firstname: user['name']&.split(' ')&.first || user['username'],
                lastname: user['name']&.split(' ')&.drop(1)&.join(' ') || '',
                email: nil,
                username: user['username'],
                location: nil,
                country: "Sin país",
                trust_level: user['trust_level'],
                avatar_template: user['avatar_template']
              }
            end
          end
          
          # Agrupar por país
          grouped = processed_users.group_by { |u| u[:country] }

          render json: grouped
        else
          render json: { error: "Failed to get directory", response: directory_response }
        end
      rescue => e
        render json: { error: "Error: #{e.message}" }
      end
    end

    def test
      # Endpoint de prueba ultra simple
      render plain: "TEST WORKS"
    end


    def debug
      # Endpoint temporal para debug - ver qué datos devuelve la API
      response.headers['Content-Type'] = 'application/json'
      response.headers['Access-Control-Allow-Origin'] = '*'
      
      # Permitir a todos los usuarios para debug
      # return render json: { error: "Unauthorized" }, status: 401 unless current_user&.admin?
      
      api_key = SiteSetting.dmu_discourse_api_key
      api_username = SiteSetting.dmu_discourse_api_username
      discourse_url = SiteSetting.dmu_discourse_api_url
      
      if api_key.blank? || discourse_url.blank?
        render json: { error: "API Key y URL de Discourse no configurados correctamente." }, status: 400
          return
        end
        
      # Simular el procesamiento completo como en el método users
      begin
        # Obtener lista de usuarios del directorio
        directory_url = "#{discourse_url}/directory_items.json?order=created&period=all&limit=10"
        directory_response = make_api_request(directory_url, api_key, api_username)
        
        if directory_response[:status_code] == 200
          directory_data = JSON.parse(directory_response[:body])
          users = directory_data['directory_items'].map { |item| item['user'] }
          
          # Procesar usuarios como en el método real
          processed_users = users.map do |user|
            # Obtener perfil completo del usuario
            user_url = "#{discourse_url}/users/#{user['username']}.json"
            user_response = make_api_request(user_url, api_key, api_username)
            
            if user_response[:status_code] == 200
              user_data = JSON.parse(user_response[:body])['user']
              location = user_data['location']
              
              country = if location.present?
                if location.include?(',')
                  location.split(',').last.strip
                else
                  location
                end
              else
                "Sin país"
              end
              
              {
                username: user_data['username'],
                name: user_data['name'],
                email: user_data['email'],
                location: location,
                country: country,
                trust_level: user_data['trust_level'],
                avatar_template: user_data['avatar_template']
              }
            else
              {
                username: user['username'],
                name: user['name'],
                location: nil,
                country: "Sin país",
                trust_level: user['trust_level'],
                avatar_template: user['avatar_template']
              }
            end
          end
          
          # Agrupar por país
          grouped = processed_users.group_by { |u| u[:country] }

        render json: { 
            total_users: processed_users.length,
            processed_users: processed_users,
            grouped_by_country: grouped,
            countries: grouped.keys,
            sample_processing: {
              original_user: users.first,
              processed_user: processed_users.first,
              location_extraction: {
                original_location: processed_users.first[:location],
                extracted_country: processed_users.first[:country]
              }
            }
          }
        else
          render json: { error: "Failed to get directory", response: directory_response }
        end
      rescue => e
        render json: { error: "Error: #{e.message}" }
      end
    end

    def save_settings
      return render json: { error: "Unauthorized" }, status: 401 unless current_user&.admin?
      
      SiteSetting.dmu_discourse_api_key = params[:dmu_discourse_api_key]
      SiteSetting.dmu_discourse_api_username = params[:dmu_discourse_api_username]
      SiteSetting.dmu_discourse_api_url = params[:dmu_discourse_api_url]
      SiteSetting.dmu_discourse_api_limit = params[:dmu_discourse_api_limit]
      render json: { success: true }
    end
    
    private
    
    def make_api_request(url, api_key, api_username)
      require 'net/http'
      require 'uri'
      require 'json'
      
      uri = URI(url)
      request_uri = URI(uri.to_s)
      http = Net::HTTP.new(request_uri.host, request_uri.port)
      http.use_ssl = true if request_uri.scheme == 'https'
      http.read_timeout = 30
      
      request = Net::HTTP::Get.new(request_uri)
      request['Api-Key'] = api_key
      request['Api-Username'] = api_username
      
      response_http = http.request(request)
      
      {
        status_code: response_http.code.to_i,
        headers: response_http.to_hash,
        body: response_http.body
      }
    end
  end

  # Registrar las rutas
  Discourse::Application.routes.append do
    get '/discourse/users' => 'discourse_users#index'
    get '/discourse/users/api' => 'discourse_users#users'
    get '/discourse/debug' => 'discourse_users#debug'
    get '/discourse/test' => 'discourse_users#test'
    post '/discourse/save_settings' => 'discourse_users#save_settings'
  end
end