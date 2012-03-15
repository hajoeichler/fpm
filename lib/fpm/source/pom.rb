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

    if self[:version].nil?
      parent = get_val(pom, "parent", {})
      self[:version] = get_val(parent, "version")
    end
    if self[:version].nil?
      raise "No valid version found in '#{pomfile}'"
    end

    self[:version] = fix_version(self[:version], "main version")

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
        optional = get_val(dep, "optional", "false")
        next if optional == "true"
        gav = "#{artifact_id}:#{version}:#{scope}"
        if version =~ /\$/
          raise "Version contains property: #{gav}"
        end
        unless scope == "test"
          self[:dependencies] << "#{libjava_name(artifact_id)} = #{fix_version(version, gav)}"
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
    jar_name.gsub(/-(r)?\d.*\.jar/,".jar")
  end

  def fix_version(v, hint="")
    unless v =~ /^\d/
      v = "0.0.0-#{v}"
      warn "Fixed version to #{v} - #{hint}"
    end
    v
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
