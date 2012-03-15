require "fpm/source"
require "fileutils"
require "fpm/rubyfixes"
require "fpm/util"
require "xmlsimple"

class FPM::Source::Pom < FPM::Source

  def get_metadata
    pomfile = paths.first
    puts "Processing #{pomfile}"
    if !File.exists?(pomfile)
      raise "Path '#{pomfile}' is not a file."
    end

    pom = XmlSimple.xml_in(pomfile)

    jarfile = pomfile.gsub(".pom", ".jar")
    if !File.exists?(jarfile)
      if get_val(pom, "packaging", "jar") != "pom"
        raise "Can not find '#{jarfile}' next to pom."
      else
        @no_jar = true
      end
    end

    self[:name] = libjava_name(get_val(pom,"artifactId"))
    self[:version] = get_val(pom,"version")

    self[:description] = get_val(pom,"description")
    self[:description] ||= get_val(pom,"name")

    self[:architecture] = "all"
    self[:category] = "universe/java"

    self[:dependencies] = []
    puts "Processing dependencies:"
    deps = get_val(pom,"dependencies", {})
    unless deps["dependency"].nil?
      deps["dependency"].each do | dep |
        artifact_id, version, = get_val(dep,"artifactId"), get_val(dep,"version")
        scope = get_val(dep,"scope","compile")
        puts "  #{artifact_id}:#{version}:#{scope}"
        unless scope == "test"
          self[:dependencies] << "#{libjava_name(artifact_id)} =#{version}"
        end
      end
    end

    # TODO: extract further field from POM
    #lisences = pom["licenses"]
    #if lisenses != null
    #  self[:license] = "foo"
    #end

    #self[:vendor] =
  end

  def get_val(node, attribute, default=nil)
    node[attribute].nil? ? default : node[attribute].first
  end

  def libjava_name(artifact_id)
     name = artifact_id.gsub("_", "-")
    "lib#{name}-java"
  end

  def ln_name(jar_name)
    jar_name.gsub(/-\d.*\.jar/,".jar")
  end

  def make_tarball!(tar_path, builddir)
    pomfile = paths.first

    ::FileUtils.mkdir_p("#{builddir}/tarbuild")
    unless @no_jar
      # create dir and store jar
      javalibdir = "#{builddir}/tarbuild/usr/share/java/"
      ::FileUtils.mkdir_p(javalibdir)
      jarfile = pomfile.gsub(".pom", ".jar")
      ::FileUtils.cp(jarfile, javalibdir)

      # create link to jar without version
      jar_name = File.basename(jarfile)
      link_name = javalibdir + ln_name(jar_name)
      puts "Creating symlink '#{link_name}' to '#{jar_name}'"
      ::FileUtils.ln_s(jar_name, link_name)
    end

    # TODO: create links to jar and pom into maven repo under /usr/share/maven-repo

    # package as tar
    ::Dir.chdir("#{builddir}/tarbuild") do
      tar(tar_path, ".")
    end

    safesystem(*["gzip", "-f", tar_path])
  end

end # class FPM::Source::Pom
