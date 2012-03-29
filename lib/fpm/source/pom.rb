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

    @artifact_id = get_val(root,"artifactId")
    @group_id = get_val(root,"groupId")
    if @group_id.nil?
      @group_id = get_val(root.elements["parent"], "groupId")
    end

    self[:version] = get_val(root,"version")
    if self[:version].nil?
      self[:version] = get_val(root.elements["parent"], "version")
    end
    if self[:version].nil?
      raise "No valid version found in '#{pomfile}'"
    end

    self[:name], self[:version] = adjust_name_version(@artifact_id, self[:version])

    self[:description] = get_val(root,"description")
    self[:description] ||= get_val(root,"name")

    self[:architecture] = "all"
    self[:category] = "universe/java"

    self[:dependencies] = []
    puts "Processing dependencies..."
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
        # TODO: lets add a commandline option to ignore dependencies in order to get rid of the fixed list here.
        if artifact_id == "scala-compiler" or artifact_id == "scalap" then
	  self[:dependencies] << "scala (>= 2.9.1)"
	  self[:dependencies] << "scala (<< 2.9.2)"
          next
        end
        if artifact_id == "scala-library" then
	  self[:dependencies] << "scala-library (>= 2.9.1)"
	  self[:dependencies] << "scala-library (<< 2.9.2)"
          next
        end
        n, v = adjust_name_version(artifact_id, version)
	self[:dependencies] << "#{n} (= #{v})"
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
#    if node.elements[attribute].nil?
#      puts "got NIL for attribute #{attribute}"
#    else
#      puts "got '#{node.elements[attribute].text} for attribute #{attribute}"
#    end
    node.elements[attribute].nil? ? default : node.elements[attribute].text
  end

  def adjust_name_version(name, version)
    name = name.gsub("_", "-")
    unless version =~ /^\d/
      version = "0.0.0-#{version}"
      warn "Fixed version to #{version} for '#{name}'"
    end
    return "lib#{name}-java", version
  end

  def ln_name(jar_name)
    jar_name.gsub(/-(r)?\d.*\.jar/,".jar")
  end

  def make_tarball!(tar_path, builddir)
    pomfile = paths.first

    ::FileUtils.mkdir_p("#{builddir}/tarbuild")

    # create maven repo content
    maven_repo_dir = "#{builddir}/tarbuild/usr/share/maven-repo/" + @group_id.gsub(".", "/") + "/" + @artifact_id + "/" + self[:version] + "/"
    ::FileUtils.mkdir_p(maven_repo_dir)
    ::FileUtils.cp(pomfile, maven_repo_dir)

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

      # create link from maven repo to versioned jar
      link_target = "../../" # two down for the artifact_id and version
      @group_id.split(".").each do # once down for each part of the group_id
        link_target = link_target + "../"
      end
      link_target = link_target + "../java/" + jar_name # one more down for "maven_repo"
      link_name = maven_repo_dir + jar_name
      puts "Creating symlink '#{link_name}' to '#{link_target}'"
      ::FileUtils.ln_s(link_target, link_name)
    end

    # package as tar
    ::Dir.chdir("#{builddir}/tarbuild") do
      tar(tar_path, ".")
    end

    safesystem(*["gzip", "-f", tar_path])
  end

end # class FPM::Source::Pom
