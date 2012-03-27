require "fpm/source"
require "fileutils"
require "fpm/rubyfixes"
require "fpm/util"
require "rexml/document"

class FPM::Source::Pom < FPM::Source

  def get_metadata
    pomfile = paths.first
    puts "Processing #{pomfile}"
    if !File.exists?(pomfile)
      raise "Path '#{pomfile}' is not a file."
    end

    file = File.new( pomfile )
    pom = REXML::Document.new file
    root = pom.root

    jarfile = pomfile.gsub(".pom", ".jar")
    if !File.exists?(jarfile)
      if get_val(root, "packaging", "jar") != "pom"
        raise "Can not find '#{jarfile}' next to pom."
      else
        @no_jar = true
      end
    end

    self[:name] = libjava_name(get_val(root,"artifactId"))
    self[:version] = get_val(root,"version")

    if self[:version].nil?
      self[:version] = get_val(root.elements["parent"], "version")
    end
    if self[:version].nil?
      raise "No valid version found in '#{pomfile}'"
    end

    self[:version] = fix_version(self[:version], "main version")

    self[:description] = get_val(root,"description")
    self[:description] ||= get_val(root,"name")

    self[:architecture] = "all"
    self[:category] = "universe/java"

    self[:dependencies] = []
    puts "Processing dependencies:"
    root.elements.each("dependencies/dependency") do | dep |
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

    # TODO: extract further field from POM
    #lisences = root["licenses"]
    #if lisenses != null
    #  self[:license] = "foo"
    #end

    #self[:vendor] =
  end

  def get_val(node, attribute, default=nil)
    if node.elements[attribute].nil?
      puts "got NIL for attribute #{attribute}"
    else
      puts node.elements[attribute].text
    end
    node.elements[attribute].nil? ? default : node.elements[attribute].text
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
