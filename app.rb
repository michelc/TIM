# encoding: UTF-8

require "sinatra"
require "sequel"
require "erb"
require "logger"
require_relative "lib/date_fr"
require_relative "lib/extend_string"

require "sinatra/reloader" if development?


# ----- Configuration de Sinatra

configure do
  # Protection contre les attaques web connues
  # (mais autorise les IFRAME pour Responsinator par exemple)
  set :protection, :except => :frame_options

  # Activation des sessions
  # (nécessaire pour conserver les périodes de consultation des projets)
  enable :sessions
end


# ----- Configuration de Sequel

# CHERCHER: Sequel / Plugins / ValidationHelpers / DEFAULT_OPTIONS messages en français

# URI.parse("sqlite://#{Dir.pwd}/_tim.db")
# = URI.parse("sqlite://C:/Ruby/_projets/TIM2/_tim.sql")
# => "sqlite://C/Ruby/_projets/TIM2/_tim.sql" !!!

DB = Sequel.connect(ENV["DATABASE_URL"] || "sqlite://timtim.db")
DB.loggers << Logger.new("debug.log") if development?

# http://stackoverflow.com/questions/23754471/sequel-dry-between-schema-migration-and-model-validate-method
Sequel::Model.raise_on_save_failure = false
Sequel::Model.plugin :auto_validations

class Workday < Sequel::Model
end

class Bookmark < Sequel::Model
end


# ----- Définition des helpers pour les vues

helpers do

  def admin? ; !session[:admin].nil? ; end
  def protected! ; halt [ 401, 'Not Authorized' ] unless admin? ; end

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

  def bookmark_title(bookmark)
    if bookmark.title == "*"
      bookmark.url.sub("https://", "").sub("http://", "").sub("www.", "").sub(/\/.*/, "")
    else
      bookmark.title
    end
  end

  def bookmark_link(bookmark)
    title = bookmark_title(bookmark)
    "<a class='lnk' href='#{bookmark.url}'>#{title}</a>"
  end

  def bookmark_tags(text, current_tag)
    tags = text.sub(current_tag, "").split(" ").map do |tag|
      "<a class='tag' href='/bookmarks/tags/#{tag}'>##{tag}</a>"
    end
    tags.join(" ")
  end

  def tag_link(tag, count)
    font_size = "font-size:#{90 + (count * 7.5)}%"
    "<a style='#{font_size}' href='/bookmarks/tags/#{tag}' title='#{count}'>#{tag}</a>"
  end

end


# ----- Définition des filtres

before "/backdoor/:id" do
  session[:admin] = true
end

before do
  # Le site est globalement protégé
  protected!
  # Le contenu est en UTF8
  headers "Content-Type" => "text/html; charset: UTF-8"
end


# ------ Gestion des droits

get "/" do
  halt [ 401, 'Not Authorized' ]
end

get "/backdoor/:id" do
  session[:admin] = nil unless params[:id] == "hello"
  redirect "/workdays"
end


# ------ Gestion des temps

# Index : affiche les 10 dernières journées
get "/workdays" do
  @workdays = Workday.limit(10).offset(1).reverse_order(:date).all
  @workday = Workday.reverse_order(:date).first
  erb :"workdays/index"
end

# Week : affiche une semaine particulière
get "/workdays/weeks/:week" do
  from = Date.parse(params[:week])
  5.times { from -= 1 unless from.cwday == 7 }
  to = from + 6
  @workdays = Workday.where(:date => from..to).order(:date).all
  erb :"workdays/index"
end

# Workday.New : formulaire pour créer une journée
get "/workdays/new" do
  @workday = Workday.new
  @workday.date = Date.today
  erb :"workdays/new"
end

# Workday.Create : enregistre une nouvelle journée
post "/workdays" do
  @workday = Workday.new(params[:workday])
  @workday = check_workday(@workday)
  # Enregistre la journée
  if @workday.save
    status 201
    redirect "/workdays"
  else
    status 400
    erb :"workdays/new"
  end
end

# Workday.Edit : formulaire pour modifier une journée
get "/workdays/edit/:id" do
  @workday = Workday[params[:id]]
  erb :"workdays/edit"
end

# Workday.Update : met à jour une journée
put "/workdays/:id" do
  @workday = Workday[params[:id]]
  params[:workday].each {|key, value| @workday[key.to_sym] = value }
  @workday = check_workday(@workday)
  #if @workday.update(params[:workday])
  if @workday.save
    status 201
    redirect "/workdays"
  else
    status 400
    erb :"workdays/edit"
  end
end

# Export : exporte les données
get '/workdays/export' do
  content_type "text/plain"
  build_markdown
end

# Import : formulaire pour importer les données
get '/workdays/import' do
  erb :"workdays/import"
end

# Import : importe les données
post '/workdays/import' do
  # Il doit y avoir des données à importer
  data = params[:data].to_s.lines.to_a
  redirect "/workdays" if data.length == 0

  # Vidage de la table
  Workday.delete

  # Réinitialisation de la séquence pour l'identifiant
  if settings.development?
    # SQLite
    DB.run("DELETE FROM sqlite_sequence WHERE name = 'workdays'")
  else
    # PostgreSQL
    DB.run("SELECT setval('workdays_id_seq', (SELECT MAX(id) FROM workdays))")
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
        # * Un commentaire (HHhMM un_projet)
        # => permet de récupérer le travail du jour
        workday.detail << line[2..-1]
      end
    end
  end
  unless workday.nil?
    workday = check_workday(workday)
    workday.save
  end

  redirect "/workdays"
end

# Report : analyse les temps par projet et par semaine
get '/workdays/reports' do
  @from = session[:from] || (Date.today << 1) + 1
  @to = session[:to] || Date.today

  @projects = Hash.new(0)
  total = 0

  @weeks = []
  weeknum = -1
  week = []
  diff = get_diff(@from)

  workdays = Workday.where(:date => @from..@to).order(:date).all
  workdays.each do |w|
    # analyse par projet
    w.detail.to_s.split("\n").each do |line|
      infos = line.match(/(\(.*\))/).to_s
      unless infos.empty?
        nb_hours = check_hour(infos)
        unless nb_hours.empty?
          project = infos.match( /\s+(.+)\)/ ).to_s.chop.strip.downcase
          minutes = get_minutes(nb_hours)
          @projects[project] += minutes
          total += minutes
        end
      end
    end
    # analyse par semaine
    if weeknum != w.date.to_date.cweek
      @weeks << week unless weeknum == -1
      week = [w.date.to_date, "?", "?", "?", "?", "?", 0, diff]
      weeknum = w.date.to_date.cweek
    end
    day = w.date.to_date.cwday
    if (w.hours - w.duration).abs > 15
      week[day] = get_hours(w.hours) + " / " + get_hours(w.duration)
      week[day] += " !" if (w.hours - w.duration) < 0
    else
      week[day] = ""
    end
    week[6] += w.hours
    week[7] += w.hours - 444
    diff += w.hours - 444
  end

  # Total analyse par projet
  @projects = Hash[@projects.sort_by { |project, minutes| project }]
  @projects["Total"] = total

  # Fin analyse par semaine
  @weeks << week unless weeknum == -1
  @weeks.reverse!
  @diff = get_diff(Date.today.next_year)

  erb :"reports/list"
end

# Report : défini la période pour analyser les temps
post '/workdays/reports' do
  session[:from] = params[:from]
  session[:to] = params[:to]

  redirect "/workdays/reports"
end

# Report.Details : liste les temps imputés sur un projet
get "/workdays/reports/:project" do
  @from = session[:from] || (Date.today << 1) + 1
  @to = session[:to] || Date.today

  @project = params[:project]
  @lines = []
  total = 0

  workdays = Workday.where(:date => @from..@to).order(:date)
  workdays.each do |w|
    w.detail.to_s.split("\n").each do |line|
      infos = line.match(/(\(.*\))/).to_s
      unless infos.empty?
        nb_hours = check_hour(infos)
        unless nb_hours.empty?
          project = infos.match( /\s+(.+)\)/ ).to_s.chop.strip.downcase
          if project == @project
            @lines << "<a href='/workdays/edit/#{w.id}'>#{w.date.strftime('%d/%m')}</a> : #{line}"
            minutes = get_minutes(nb_hours)
            total += minutes
          end
        end
      end
    end
  end
  @project += " : " + get_days(total).to_s

  erb :"reports/project"
end


# ------ Gestion des liens


# Bookmark.Index : affiche les 25 dernières liens
get "/bookmarks" do
  session[:current_tag] = "*"
  @bookmarks = Bookmark.limit(25).reverse_order(:id).all
  @bookmark = Bookmark.new
  @tags = get_tags
  erb :"bookmarks/index"
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
    session[:current_tag] = "*" unless @bookmark.tags.include? session[:current_tag]
    redirect "/bookmarks/tags/#{session[:current_tag]}" unless session[:current_tag] == "*"
    redirect "/bookmarks"
  else
    status 400
    erb :"bookmarks/new"
  end
end

# Bookmark.Edit : formulaire pour modifier un lien
get "/bookmarks/edit/:id" do
  @bookmark = Bookmark[params[:id]]
  erb :"bookmarks/edit"
end

# Bookmark.Update : met à jour un lien
put "/bookmarks/:id" do
  @bookmark = Bookmark[params[:id]]
  params[:bookmark].each {|key, value| @bookmark[key.to_sym] = value }
  @bookmark = check_bookmark(@bookmark)
  if @bookmark.save
    status 201
    redirect "/bookmarks/tags/#{session[:current_tag]}" unless session[:current_tag] == "*"
    redirect "/bookmarks"
  else
    status 400
    erb :"bookmarks/edit"
  end
end


# Bookmark.Tags : affiche les liens liés à un tag
get "/bookmarks/tags/:tag" do
  session[:current_tag] = params[:tag]
  tag = params[:tag]
  tag = "%#{tag}%"
  @bookmarks = Bookmark.where(Sequel.like(:tags, tag)).reverse_order(:id).all
  @bookmark = Bookmark.new
  @tags = get_tags
  erb :"bookmarks/index"
end


# ----- Fonctions utilitaires gestion des temps

def build_markdown
  current_year = 0
  current_week = 0
  markdown = ""

  workdays = Workday.order(:date).all
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

def get_diff(max_date)
  nb_minutes = Workday.where{ date < max_date }.sum(:hours) || 0
  nb_days = Workday.where{ date < max_date }.count || 0
  diff  = 497              # écart de 8h17 au 1/1/14
  diff += nb_minutes       # nb minutes travaillées
  diff -= (nb_days * 444)  # nb jours * 7h24

  diff
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

def get_tags
  tags = Hash.new(0)
  bookmarks = Bookmark.select(:tags).all
  bookmarks.each do |bookmark|
    bookmark.tags.split(" ").each do |tag|
      tags[tag] += 1
    end
  end
  Hash[tags.sort_by { |tag, count| tag }]
end
