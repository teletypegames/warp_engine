require "zip"
require "chunky_png"

ActiveRecord::Base.logger = nil

admin_email    = ENV.fetch("ADMIN_EMAIL", "admin@example.org")
admin_password = ENV.fetch("ADMIN_PASSWORD", "warpengine")

AdminUser.find_or_create_by!(email: admin_email) do |user|
  user.password = admin_password
  user.password_confirmation = admin_password
end

GAMES = [
  { name: "starhop", title: "Star Hop", platform: "love", version: "1.0.0", category: "arcade",
    color: [ 250, 204, 21 ], background: "#0b1026", highlighted: true,
    desc: "Hop from star to star before the night runs out." },
  { name: "pixel-garden", title: "Pixel Garden", platform: "phaser", version: "0.3.0", category: "puzzle",
    color: [ 74, 222, 128 ], background: "#10291a", highlighted: false,
    desc: "Grow a garden one pixel at a time." },
  { name: "retro-racer", title: "Retro Racer", platform: "love", version: "2.1.0", category: "racing",
    color: [ 248, 113, 113 ], background: "#2a0f12", highlighted: false,
    desc: "Eight-bit laps on a neon track." }
].freeze

def game_html(game)
  r, g, b = game[:color]
  <<~HTML
    <!doctype html>
    <html><head><meta charset="utf-8"><title>#{game[:title]}</title>
    <style>html,body{margin:0;height:100%;background:#{game[:background]};color:#fff;font:16px monospace}
    canvas{display:block;margin:0 auto}p{text-align:center}</style></head>
    <body><p>#{game[:title]} — click the square</p><canvas id="c" width="480" height="320"></canvas>
    <script>
    const c=document.getElementById("c"),x=c.getContext("2d");let p={x:40,y:40,dx:3,dy:2},s=0;
    c.onclick=e=>{const r=c.getBoundingClientRect(),mx=e.clientX-r.left,my=e.clientY-r.top;
    if(mx>p.x&&mx<p.x+32&&my>p.y&&my<p.y+32){s++;p.dx*=1.15;p.dy*=1.15}};
    (function f(){p.x+=p.dx;p.y+=p.dy;if(p.x<0||p.x>448)p.dx*=-1;if(p.y<0||p.y>288)p.dy*=-1;
    x.fillStyle="#{game[:background]}";x.fillRect(0,0,480,320);x.fillStyle="rgb(#{r},#{g},#{b})";
    x.fillRect(p.x,p.y,32,32);x.fillStyle="#fff";x.fillText("score "+s,8,16);requestAnimationFrame(f)})();
    </script></body></html>
  HTML
end

def write_zip(path, entries)
  FileUtils.rm_f(path)
  Zip::File.open(path, Zip::File::CREATE) do |zip|
    entries.each { |name, content| zip.get_output_stream(name) { |io| io.write(content) } }
  end
end

def cover_image(game)
  png = ChunkyPNG::Image.new(320, 180, ChunkyPNG::Color.from_hex(game[:background]))
  accent = ChunkyPNG::Color.rgb(*game[:color])
  png.rect(120, 50, 200, 130, accent, accent)
  png.rect(8, 8, 311, 171, accent)

  filename = "seed-#{game[:name]}.png"
  FileUtils.mkdir_p(Image.upload_path)
  png.save(File.join(Image.upload_path, filename))
  Image.find_or_create_by!(filename: filename) do |image|
    image.original_filename = "#{game[:name]}.png"
    image.content_type = "image/png"
  end
end

root = WarpEngine.config.file_container_path
FileUtils.mkdir_p(root)

GAMES.each do |game|
  next if WarpEngine::Software.exists?(name: game[:name])

  base = "#{game[:name]}-#{game[:version]}"
  metadata = game.slice(:name, :title, :desc, :category).merge(author: "WarpEngine Example", license: "MIT")
  File.write(File.join(root, "#{base}.metadata.json"), JSON.pretty_generate(metadata))
  write_zip(File.join(root, "#{base}.html.zip"), "index.html" => game_html(game))
  write_zip(File.join(root, "#{base}-win-x64.zip"), "README.txt" => "#{game[:title]} #{game[:version]} for Windows\n")

  input = WarpEngine::PublishInputDto.new(platform: game[:platform], name: game[:name], version: game[:version])
  release = WarpEngine::PublishService.new.publish(input)

  software = WarpEngine::Software.find_by!(name: game[:name])
  software.update!(status: "released", highlighted: game[:highlighted])
  software.software_images.create!(image: cover_image(game), is_default: true, position: 0)

  rand(3..12).times do |i|
    WarpEngine::Download.create!(file_path: "#{base}-win-x64.zip", release: release,
                                 ip_address: "192.0.2.#{i + 1}", user_agent: "seed")
  end

  puts "Seeded #{game[:title]} #{game[:version]} (#{game[:platform]})"
end

puts "Admin: #{admin_email} / #{admin_password}"
