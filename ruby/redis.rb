require 'redis'

def redis_config
  @redis_config ||= {
    host: ENV['ISHOCON2_REDIS_HOST'] || 'localhost',
  }
end

def redis
  @redis ||= Redis.new(redis_config)
end
