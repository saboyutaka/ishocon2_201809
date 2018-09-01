require 'mysql2'
require 'mysql2-cs-bind'

def config
  @config ||= {
    db: {
      host: ENV['ISHOCON2_DB_HOST'] || 'localhost',
      port: ENV['ISHOCON2_DB_PORT'] && ENV['ISHOCON2_DB_PORT'].to_i,
      username: ENV['ISHOCON2_DB_USER'] || 'ishocon',
      password: ENV['ISHOCON2_DB_PASSWORD'] || 'ishocon',
      database: ENV['ISHOCON2_DB_NAME'] || 'ishocon2'
    }
  }
end

def db
  return Thread.current[:ishocon2_db] if Thread.current[:ishocon2_db]
  client = Mysql2::Client.new(
    host: config[:db][:host],
    port: config[:db][:port],
    username: config[:db][:username],
    password: config[:db][:password],
    database: config[:db][:database],
    reconnect: true
  )
  client.query_options.merge!(symbolize_keys: true)
  Thread.current[:ishocon2_db] = client
  client
end
