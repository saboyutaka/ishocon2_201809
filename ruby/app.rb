require 'sinatra/base'
require 'erubis'
require 'oj'

require_relative './redis'
require_relative './db'

module Ishocon2
  class AuthenticationError < StandardError;
  end
  class PermissionDenied < StandardError;
  end
end

def render_vote(message = '')
  $rendered_vote.sub("{{MESSAGE}}", message)
end

$users = {}
$candidates = db.xquery('select * from candidates').to_a
$vote_count = 0
$rendered_vote = File.read('data/rendered_vote.html')
$rendered_vote_ok = render_vote('投票に成功しました')
$rendered_vote_invalid_user = render_vote('個人情報に誤りがあります')
$rendered_vote_empty_candidate = render_vote('候補者を記入してください')
$rendered_vote_invalid_candidate = render_vote('候補者を正しく記入してください')
$rendered_vote_no_keyword = render_vote('投票理由を記入してください')
$rendered_vote_over_voting = render_vote('投票数が上限を超えています')

class Ishocon2::WebApp < Sinatra::Base
  session_secret = ENV['ISHOCON2_SESSION_SECRET'] || 'showwin_happy'
  use Rack::Session::Cookie, key: 'rack.session', secret: session_secret
  set :erb, escape_html: true
  set :public_folder, File.expand_path('../public', __FILE__)
  set :protection, true

  configure :development do
    require 'sinatra/reloader'
    register Sinatra::Reloader

    require 'rack-mini-profiler'
    use Rack::MiniProfiler

    require 'rack-lineprof'
    use Rack::Lineprof, profile: 'app.rb'
  end

  helpers do
    def voice_of_supporter(candidate_ids)
      query = <<~SQL
        SELECT keyword
        FROM voices
        WHERE candidate_id IN (?)
        GROUP BY keyword
        ORDER BY SUM(count) DESC
        LIMIT 10
      SQL
      db.xquery(query, candidate_ids).map { |a| a[:keyword] }
    end

    def db_initialize
      db.query('DELETE FROM votes')
      db.query('DELETE FROM voices')
    end

    def redis_initialize
      redis.flushall
      set_rendered_vote
      set_candidate_votes
      set_sex_votes
    end

    def view_initialize
      purge_view_cache
    end

    def purge_view_cache
      dir = File.expand_path('../public', __FILE__)
      Dir.glob("#{dir}/**/*.html").each { |file| FileUtils.rm(file) }
    end

    def set_rendered_vote
      redis.set('rendered_vote', erb(:vote, locals: { candidates: $candidates }))
    end

    def set_candidate_votes
      $candidates.each { |c| redis.set candidate_vote_key(c), 0 }
    end

    def set_sex_votes
      redis.set('man:vote', 0)
      redis.set('woman:vote', 0)
    end

    def candidate_vote_key(candidate)
      "party:#{candidate[:political_party]}:#{candidate[:id]}:vote"
    end

    def stored_parties
      %w(夢実現党 国民10人大活躍党 国民元気党 国民平和党)
    end

    def get_candidate(id)
      $candidates.find { |c| c[:id] == id }
    end

    def get_candidate_vote(candidate)
      redis.get("party:#{candidate[:political_party]}:#{candidate[:id]}:vote").to_i
    end

    def get_party_vote(party_name)
      candidates_keys = redis.keys "party:#{party_name}:*:vote"
      redis.mget(candidates_keys).map(&:to_i).sum
    end

    def view_cache?
      ENV['RACK_ENV'] == 'production' && $vote_count > 200
    end
  end

  get '/' do
    # 候補者別の投票数
    candidates = []
    candidates_result = $candidates.map do |candidate|
      [candidate[:id], get_candidate_vote(candidate)]
    end
    sorted = candidates_result.sort { |a, b| a[1] <=> b[1] }.reverse
    sorted.slice(0...10).each do |res|
      candidate = get_candidate(res[0])
      candidate[:count] = res[1]
      candidates << candidate
    end
    last_candidate_result = sorted.last
    if last_candidate_result
      candidate = get_candidate(last_candidate_result[0])
      candidate[:count] = last_candidate_result[1]
      candidates << candidate
    end

    # 政党別の投票数
    parties = {}
    stored_parties.map { |party_name| parties[party_name] = get_party_vote(party_name) }

    # 性別の投票数
    man_votes = redis.get('man:vote').to_i
    woman_votes = redis.get('woman:vote').to_i
    sex_ratio = { '男': man_votes, '女': woman_votes }

    rendered_view = erb :index, locals: { candidates: candidates,
      parties: parties,
      sex_ratio: sex_ratio }

    File.write('public/index.html', rendered_view) if view_cache?

    rendered_view
  end

  get '/candidates/:id' do
    id = params[:id].to_i
    candidate = get_candidate(id)
    return redirect '/' if candidate.nil?

    votes = get_candidate_vote(candidate)
    keywords = voice_of_supporter([id])

    rendered_view = erb :candidate, locals: { candidate: candidate,
      votes: votes,
      keywords: keywords }

    File.write("public/candidates/#{id}.html", rendered_view) if view_cache?

    rendered_view
  end

  get '/political_parties/:name' do
    votes = get_party_vote(params[:name])
    candidates = $candidates.select { |c| c[:political_party] == params[:name] }
    candidate_ids = candidates.map { |c| c[:id] }
    keywords = voice_of_supporter(candidate_ids)

    rendered_view = erb :political_party, locals: { political_party: params[:name],
      votes: votes,
      candidates: candidates,
      keywords: keywords }

    File.write("public/political_parties/#{params[:name]}.html", rendered_view) if view_cache?

    rendered_view
  end

  get '/vote' do
    render_vote
  end

  post '/vote' do
    mynumber = params[:mynumber]
    user = $users[mynumber]
    if user.nil?
      user = db.xquery('SELECT * FROM users WHERE mynumber = ?', mynumber).first
      $users[:mynumber] = user
    end

    return $rendered_vote_invalid_user if user.nil? || user[:name] != params[:name] || user[:address] != params[:address]
    return $rendered_vote_empty_candidate if params[:candidate].nil? || params[:candidate] == ''

    candidate = $candidates.find { |h| h[:name] == params[:candidate] }

    return $rendered_vote_invalid_candidate if candidate.nil?
    return $rendered_vote_no_keyword if params[:keyword].nil? || params[:keyword] == ''

    key = "user:#{user[:id]}:vote"

    redis.setnx(key, user[:votes])

    voted_count = redis.get(key).to_i
    voting_count = params[:vote_count].to_i

    return $rendered_vote_over_voting if voted_count < voting_count

    voice = db.xquery('SELECT * FROM voices WHERE candidate_id = ? AND keyword = ?', candidate[:id], params[:keyword]).first
    if voice
      db.xquery('UPDATE voices SET count = ? WHERE id = ?', voice[:count] + voting_count, voice[:id])
    else
      db.xquery('INSERT INTO voices (candidate_id, keyword, count) VALUES (?, ?, ?)', candidate[:id], params[:keyword], voting_count)
    end

    redis.incrby candidate_vote_key(candidate), voting_count

    if candidate[:sex] == '男'
      redis.incrby 'man:vote', voting_count
    else
      redis.incrby 'woman:vote', voting_count
    end

    redis.decrby key, voting_count

    $vote_count += 1

    return $rendered_vote_ok
  end

  def user_vote(key)
    user_vote = redis.get key
    if user_vote.nil?
      redis.set key, user[:votes]
      user_user[:votes]
    else
      user_vote.to_i
    end
  end

  get '/initialize' do
    db_initialize
    redis_initialize
    view_initialize
    'ok'
  end

  get '/purge' do
    purge_view_cache
    'ok'
  end

  # get '/init' do
  #   prepare_users
  # end

  # def prepare_users
  #   0.step(4000000, 100) do |n|
  #     puts n
  #     db.xquery("SELECT * FROM users LIMIT 100 OFFSET #{n}").to_a.each do |user|
  #       $users[user[:mynumber]] ||= user
  #       print '.'
  #     end
  #     puts ''
  #   end
  # end
end
