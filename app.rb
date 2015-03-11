require 'rubygems'
require 'RMagick'
require 'sinatra'
require 'chunky_png'
require 'open-uri'
require 'json'
require 'chunky_png/rmagick'

include ChunkyPNG

$chars = " !\"#$%'()&*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`{|}~"
$ascii = []
$used = []

$queue = Queue.new

def handleImage item

  begin
    puts "[#{item[:id]}] Starting"

    item[:progress] = 'fetching image'
    begin
      imageData = open(item[:url]).read
    rescue
      item[:progress] = 'failed; couldn\'t download'
      return
    end
    puts "[#{item[:id]}] Retrieved Image"
    if imageData.length == 0
      puts "[#{item[:id]}] Failed - Bad image"
      item[:progress] = 'failed; bad image'
      return
    end
    puts "[#{item[:id]}] Writing Image"
    open('temp'+item[:id].to_s+'.png', 'wb'){|f|f.write(imageData)}
    puts "[#{item[:id]}] Downloaded image"
    item[:progress] = 'loading image'
    begin
      img = Image.from_file('temp'+item[:id].to_s+'.png')
    rescue
      item[:progress] = 'failed; couldn\'t load'
      return
    end
    begin
      rmagicimg = ChunkyPNG::RMagick.export(img)
      img = ChunkyPNG::RMagick.import(rmagicimg.quantize($chars.length-3))
    rescue
      item[:progress] = 'failed; couldn\'t quantize colors'
      return
    end
    item[:progress] = 'processing image'

    width = img.dimension.width
    height = img.dimension.height

    if width > 1080 || height > 1080
      item[:progress] = 'failed; too large'
      return
    end

    colors = ["1.000 1.000 1.000 1.000"]

    width.times {|x|
      height.times {|y|
        r = '%.3f' % (Color.r(img[x,y])/255.0)
        g = '%.3f' % (Color.g(img[x,y])/255.0)
        b = '%.3f' % (Color.b(img[x,y])/255.0)
        if Color.a(img[x,y]) != 255
          img[x,y] = ChunkyPNG::Color.rgba(255,255,255,255)
          next
        end
        
        c = "#{r} #{g} #{b} 1.000"
        colors << c if !colors.include?(c)
      }
    }
    

    #puts "Colors #{colors.length}"
    if colors.length > $chars.length
      item[:progress] = 'failed; too many colors'
      return
    end

    colors.length.times {|c|

      item[:data] += "COLOR\t#{$chars[c]}\t#{colors[c]}\n"
    }
    item[:progress] = 'generating image'

    height.times {|y|
      width.times {|x|
        r = '%.3f' % (Color.r(img[x,y])/255.0)
        g = '%.3f' % (Color.g(img[x,y])/255.0)
        b = '%.3f' % (Color.b(img[x,y])/255.0)
        a = '%.3f' % (Color.a(img[x,y])/255.0)
        c = "#{r} #{g} #{b} #{a}"
        i = colors.index(c)
        item[:data] += $chars[i] || ' '
      }
      item[:data] += "\n"
    }
    item[:data] = item[:data] + "\n"
    item[:progress] = 'generated'
    item[:downloadable] = true

  rescue
    item[:progress] = 'failed; error ' + $!.backtrace
  end

end

get '/generate' do

  url = params[:url]

  if !(/\.png$/ =~ url)
    @msg = "Not a png"

  elsif $used.include? url
    @msg = "already generated"

  else
    $used << url

    id = $ascii.length + 1
    item = {url: url, id: id, progress: 'queued', data: '', downloadable: false}
    $ascii << item
    @msg = "Starting Item"
    
    Thread.start {
      handleImage item
    }

  end
  erb :post
end

get '/listdata' do
  data = $ascii.map { |a|
    {
      id: a[:id],
      url: a[:url],
      state: a[:progress],
      download: a[:downloadable]
    }
  }.to_json
  data
end

get '/ascii/:id' do
  if $ascii[params[:id].to_i-1]
    content_type 'text/plain'
    $ascii[params[:id].to_i-1][:data]
  else
    pass
  end
end

get '/' do
  erb :index
end