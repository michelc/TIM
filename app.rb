# encoding: UTF-8

require "sinatra"
require "data_mapper"
require "erb"
require_relative "lib/date_fr"
require_relative "lib/extend_string"

require "sinatra/reloader" if development?


# ----- Calcul écart heures travaillées / obligatoires
#
# SELECT Nb_Heures / 60 AS Heures
#      , Nb_Heures - ((Nb_Heures / 60) * 60) AS Minutes
# FROM   (SELECT 497              -- écart de 8h17 au 1/1/14
#              + SUM(hours)       -- nb heures travaillées
#              - (COUNT(*) * 444) -- nb jours * 7h24
#              AS Nb_Heures
#         FROM   workdays
#         WHERE  date <= '2015-01-01')


# ----- Configuration de Sinatra

configure do
  # Protection contre les attaques web connues
  # (mais autorise les IFRAME pour Responsinator par exemple)
  set :protection, :except => :frame_options

  # Activation des sessions
  # (nécessaire pour conserver les périodes de consultation des tags)
  enable :sessions
end


# ----- Configuration de DataMapper

DataMapper::Logger.new("debug.log", :debug) if development?
DataMapper.setup(:default, ENV["DATABASE_URL"] || "sqlite3://#{Dir.pwd}/_tim.db")

class Workday
  include DataMapper::Resource

  property :id,       Serial
  property :date,     DateTime,   :required => true, :messages => { :presence => "Le jour est obligatoire" }
  property :am_start, String,     :length => 5
  property :am_end,   String,     :length => 5
  property :pm_start, String,     :length => 5
  property :pm_end,   String,     :length => 5
  property :hours,    Integer
  property :detail,   Text
  property :duration, Integer
end

class Bookmark
  include DataMapper::Resource

  property :id          , Serial
  property :url         , String,
                          :length => 255,
                          :required => true,
                          :messages => { :presence => "L'url du lien est obligatoire" },
                          :unique_index => true
  property :title       , String,
                          :length => 100,
                          :required => true,
                          :messages => { :presence => "Le titre est obligatoire" }
  property :description , String,
                          :length => 2000,
                          :default => ""
  property :tags        , String,
                          :length => 255,
                          :default => ""
  property :create_at   , DateTime,
                          :default => Date.today
end

DataMapper.auto_upgrade!


# ----- Définition des helpers pour les vues

helpers do

  def day_title(workday)
    # get day name (Lundi 12)
    title = workday.date.strftime("%A %d")
    # return day name and hours
    title += " // " + get_hours(workday.hours)
    title += " // " + get_hours(workday.duration)
    title += " // KO" if (workday.hours - workday.duration).abs > 15
    title
  end

  def input_date(value)
    text = ""
    if value.respond_to?(:strftime)
      text = value.strftime("%Y-%m-%d")
    end
    text
  end

  def get_hours(minutes_as_int)
    h = minutes_as_int / 60
    m = minutes_as_int - (h * 60)

    hh_mm = "%dh%02d" % [ h, m ]
    hh_mm.sub("h00", "h")
  end

  def get_days(minutes_as_int)
    d = minutes_as_int / 450.0

    (d*4).round / 4.0
  end

  def link_title(bookmark)
    title = if bookmark.title == "*"
              bookmark.url.sub("https://", "").sub("http://", "").sub("www.", "").sub(/\/.*/, "")
            else
              bookmark.title
            end
    "<a class='lnk' href='#{bookmark.url}'>#{title}</a>"
  end

  def link_group(item, count)
    css = "font-size:#{90 + (count * 7.5)}%"
    "<a style='#{css}' href='/bookmarks/tags/#{item}' title='#{count}'>#{item}</a>"
  end

  def list_tags(text, current_tag)
    tags = text.sub(current_tag, "").split(" ").map do |tag|
      "<a class='tag' href='/bookmarks/tags/#{tag}'>##{tag}</a>"
    end
    tags.join(" ")
  end

end


# ----- Définition des filtres

before do
  # Le contenu est en UTF8
  headers "Content-Type" => "text/html; charset: UTF-8"
end


# ------ Gestion des temps

# Index : affiche les 10 dernières journées
get "/" do
  @workdays = Workday.all(:offset => 1, :limit => 10, :order => [:date.desc])
  @workday = Workday.first(:order => [:date.desc])
  erb :index
end

# Workday.New : formulaire pour créer une journée
get "/new" do
  @workday = Workday.new
  @workday.date = Date.today
  erb :new
end

# Workday.Create : enregistre une nouvelle journée
post "/" do
  @workday = Workday.new(params[:workday])
  @workday = check_workday(@workday)
  # Enregistre la journée
  if @workday.save
    status 201
    redirect "/"
  else
    status 400
    erb :new
  end
end

# Workday.Edit : formulaire pour modifier une journée
get "/edit/:id" do
  @workday = Workday.get(params[:id])
  erb :edit
end

# Workday.Update : met à jour une journée
put "/:id" do
  @workday = Workday.get(params[:id])
  @workday.attributes = params[:workday]
  @workday = check_workday(@workday)
  if @workday.save
    status 201
    redirect "/"
  else
    status 400
    erb :edit
  end
end

# Export : exporte les données
get '/export' do
  content_type "text/plain"
  build_markdown
end

# Import : formulaire pour importer les données
get '/import' do
  erb :import
end

# Import : importe les données
post '/import' do
  # Il doit y avoir des données à importer
  data = params[:data].to_s.lines.to_a
  redirect "/" if data.length == 0

  # Vidage de la table
  Workday.destroy

  # Réinitialisation de la séquence pour l'identifiant
  adapter = DataMapper.repository(:default).adapter
  if settings.development?
    # SQLite
    adapter.execute("DELETE FROM sqlite_sequence WHERE name = 'workdays'")
  else
    # PostgreSQL
    adapter.execute("SELECT setval('workdays_id_seq', (SELECT MAX(id) FROM workdays))")
  end

  # Importation séquentielle des données
  current_year = 0
  current_month = 0
  workday = nil
  data.each do |line|
    if line.start_with? "# "
      # ## Année 9999
      # => permet de récupérer l'année
      current_year = line.split(" ").last.to_i
    elsif line.start_with? "## "
      # ## Semaine du 99 au 99 NomMois
      # ## Semaine du 13 au 17 Janvier
      # => permet de récupérer le mois
      unless workday.nil?
        workday = check_workday(workday)
        workday.save
        workday = nil
      end
      parts = line.split(" ")
      month_name = parts.last
      current_month = Date::MONTHNAMES.index(month_name)
      # Cas particuliers
      # ## Semaine du 31 Mars au 4 Avril
      # => il faut utiliser le mois précédant
      current_month -= 1 if parts[3].to_i > parts[5].to_i
      # ## Semaine du 29 Décembre au 2 Janvier
      # => le mois précédant janvier est décembre
      current_month = 12 if current_month == 0
    elsif line.start_with? "### "
      # ### NomJour 99 (HHhMM)
      # => permet de récupérer le jour du mois
      unless workday.nil?
        workday = check_workday(workday)
        workday.save
      end
      current_day = line.split(" ")[2].to_i
      # Cas particulier
      unless workday.nil?
        # ## Semaine du 31 au 4 Avril
        # ### Lundi 31
        # ### Mardi 1
        # => il faut utiliser le mois suivant
        #    (soit Avril puisqu'on avait pris le mois précédant auparavant)
        current_month += 1 if workday.date.day > current_day
      end
      workday = Workday.new
      workday.date = DateTime.new(current_year, current_month, current_day)
      workday.detail = ""
    elsif line.start_with? "* "
      if workday.am_start.nil?
        # * HHhMM / HHhMM et HHhMM / HHhMM
        # => permet de récupérer les horaires du jour
        hours = line.sub("et", "/").split("/")
        workday.am_start = hours[0]
        workday.am_end = hours[1]
        workday.pm_start = hours[2]
        workday.pm_end = hours[3]
        workday.pm_end = hours[3].split(" ")[0] if hours[3].include? " "
      else
        # * Un commentaire (HHhMM un_tag)
        # => permet de récupérer le travail du jour
        workday.detail << line[2..-1]
      end
    end
  end
  unless workday.nil?
    workday = check_workday(workday)
    workday.save
  end

  redirect "/"
end

# Tags : affiche les temps groupés par tags
get '/tags' do
  @from = session[:from] || (Date.today << 1) + 1
  @to = session[:to] || Date.today

  @tags = Hash.new(0)
  total = 0

  workdays = Workday.all(:date => @from..@to, :order => [:date.asc])
  workdays.each do |w|
    w.detail.to_s.split("\n").each do |line|
      infos = line.match(/(\(.*\))/).to_s
      unless infos.empty?
        nb_hours = check_hour(infos)
        unless nb_hours.empty?
          tag = infos.match( /\s+(.+)\)/ ).to_s.chop.strip.downcase
          min = get_minutes(nb_hours)
          @tags[tag] += min
          total += min
        end
      end
    end
  end

  @tags = Hash[@tags.sort_by { |tag, min| tag }]
  @tags["Total"] = total

  erb :tags_list
end

# Tags : défini la période pour grouper les temps par tag
post '/tags' do
  session[:from] = params[:from]
  session[:to] = params[:to]

  redirect "/tags"
end

# Tags.Details
get "/tags/:tag" do
  @from = session[:from] || (Date.today << 1) + 1
  @to = session[:to] || Date.today

  @tag = params[:tag]
  @lines = []
  total = 0

  workdays = Workday.all(:date => @from..@to, :order => [:date.asc])
  workdays.each do |w|
    w.detail.to_s.split("\n").each do |line|
      infos = line.match(/(\(.*\))/).to_s
      unless infos.empty?
        nb_hours = check_hour(infos)
        unless nb_hours.empty?
          tag = infos.match( /\s+(.+)\)/ ).to_s.chop.strip.downcase
          if tag == @tag
            @lines << "<a href='/edit/#{w.id}'>#{w.date.strftime('%d/%m')}</a> : #{line}"
            min = get_minutes(nb_hours)
            total += min
          end
        end
      end
    end
  end
  @tag += " : " + get_days(total).to_s

  erb :tags_show
end


# ------ Gestion des liens


# Bookmark.Index : affiche les 25 dernières liens
get "/bookmarks" do
  @bookmarks = Bookmark.all(:offset => 0, :limit => 25, :order => [:id.desc])
  @bookmark = Bookmark.new
  @groups = group_tags
  @current_tag = ""
  erb :"bookmarks/list"
end

# Bookmark.New : formulaire pour créer un lien
get "/bookmarks/new" do
  @bookmark = Bookmark.new
  erb :"bookmarks/new"
end

# Bookmark.Create : enregistre un nouveau lien
post "/bookmarks" do
  @bookmark = Bookmark.new(params[:bookmark])
  @bookmark = check_bookmark(@bookmark)
  if @bookmark.save
    status 201
    redirect "/bookmarks"
  else
    status 400
    erb :"bookmarks/new"
  end
end

# Bookmark.Edit : formulaire pour modifier un lien
get "/bookmarks/edit/:id" do
  @bookmark = Bookmark.get(params[:id])
  erb :"bookmarks/edit"
end

# Bookmark.Update : met à jour un lien
put "/bookmarks/:id" do
  @bookmark = Bookmark.get(params[:id])
  @bookmark.attributes = params[:bookmark]
  @bookmark = check_bookmark(@bookmark)
  if @bookmark.save
    status 201
    redirect "/bookmarks"
  else
    status 400
    erb :"bookmarks/edit"
  end
end


# Bookmark.Tags : affiche les liens liés à un tag
get "/bookmarks/tags/:tag" do
  tag = params[:tag]
  tag = "%#{tag}%"
  @bookmarks = Bookmark.all(:tags.like => tag, :order => [:id.desc])
  @bookmark = Bookmark.new
  @groups = group_tags
  @current_tag = params[:tag]
  erb :"bookmarks/list"
end


# ----- Fonctions utilitaires gestion des temps

def build_markdown
  current_year = 0
  current_week = 0
  markdown = ""

  workdays = Workday.all(:order => [:date.asc])
  workdays.each do |w|
    year = w.date.year
    if current_year != year
      current_year = year
      markdown << "# Année #{year}\n"
      markdown << "\n"
    end
    week = w.date.strftime("%V").to_i
    if current_week != week
      current_week = week
      friday = w.date + 5 - w.date.wday
      markdown << "\n"
      markdown << "## Semaine du #{w.date.mday}"
      markdown << " #{w.date.strftime('%B')}" unless (w.date.month == friday.month)
      markdown << " au #{friday.mday} #{friday.strftime('%B')}\n"
      markdown << "\n"
    end
    markdown << "### #{w.date.strftime('%A %d')} (#{get_hours(w.hours)})\n"
    markdown << "\n"
    markdown << "* #{w.am_start} / #{w.am_end} et #{w.pm_start} / #{w.pm_end}\n"
    w.detail.to_s.split("\n").each do |line|
      markdown << "* #{line.chomp}\n"
    end
    markdown << "\n"
  end
  markdown
end

def check_workday(workday)
  if workday.detail.start_with? "!"
    workday.am_start = "8h"
    workday.am_end = "12h"
    workday.pm_start = "14h"
    workday.pm_end = "17h24"
  else
    workday.am_start = check_hour(workday.am_start)
    workday.am_end = check_hour(workday.am_end)
    workday.pm_start = check_hour(workday.pm_start)
    workday.pm_end = check_hour(workday.pm_end)
  end
  workday.hours = sum_hours(workday)
  workday.duration = sum_duration(workday.detail)
  workday.detail = (workday.detail.to_s.split("\n").map { |l| l.chomp }).join("\n")
  workday
end

def check_hour(text)
  hour = text.match(/(([0-9]|0[0-9]|1[0-9]|2[0-3])(h|:|\.)[0-5][0-9])/).to_s
  if hour.empty?
    hour = text.match(/([0-9]|0[0-9]|1[0-9]|2[0-3])(h)/).to_s
  end
  hour = hour.sub(/:/, "h")
  hour = hour.sub(/\./, "h")
  hour = hour.sub(/h00/, "h")
  if hour.start_with?("0")
    hour.slice!(0) unless hour.start_with? "0h"
  end
  hour
end

def xls_hour(hour)
  minutes = get_minutes(hour)
  h = minutes / 60
  m = minutes - (h * 60)

  "%02d:%02d" % [ h, m ]
end

def sum_hours(workday)
  am_start = get_minutes(workday.am_start)
  am_end = get_minutes(workday.am_end)
  am = am_end - am_start
  return 0 if am < 0

  pm_start = get_minutes(workday.pm_start)
  pm_end = get_minutes(workday.pm_end)
  pm = pm_end - pm_start
  return am if pm < 0

  am + pm
end

def get_minutes(hour_as_text)
  temp = hour_as_text.split("h")
  (temp[0].to_i * 60) + temp[1].to_i
end

def sum_duration(detail)
  duration = 0
  detail.to_s.split("\n").each do |line|
    infos = line.match(/(\(.*\))/).to_s
    unless infos.empty?
      nb_hours = check_hour(infos)
      duration += get_minutes(nb_hours)
    end
  end

  duration
end


# ----- Fonctions utilitaires gestion des liens

def check_bookmark(bookmark)
  bookmark.tags = text_to_tags(bookmark.tags)
  bookmark
end

def text_to_tags(text)
  # Transforme le texte en minuscule sans accents
  text = text.removeaccents.downcase
  # Ne conserve que l'espace, les lettres et les nombres, le tiret et le point
  text.gsub!(/[^ a-z0-9\-\.]/, "")
  # Découpage et vérification des différents tags
  tags = text.strip.split(/\s+/).map do |tag|
    tag
  end
  # Renvoie les tags triés sous forme de texte
  tags.sort.uniq.join(" ")
end

def group_tags
  groups = Hash.new(0)
  total = 0
  bookmarks = Bookmark.all(:fields => [:tags])
  bookmarks.each do |bookmark|
    bookmark.tags.split(" ").each do |tag|
      groups[tag] += 1
      total += 1
    end
  end
  Hash[groups.sort_by { |tag, nb| tag }]
end
