require "fpm/source"
require "fileutils"
require "fpm/rubyfixes"
require "fpm/util"
require "xmlsimple"

class FPM::Source::Pom < FPM::Source

  def get_metadata
    pomfile = paths.first
    if !File.exists?(pomfile)
      raise "Path '#{pomfile}' is not a file."
    end
    pom = XmlSimple.xml_in(pomfile)
    self[:name] = libjava_name(pom["artifactId"].to_s)
    self[:version] = pom["version"].to_s

    desc = pom["description"]
    if desc == nil
      desc = pom["name"]
    end
    if desc != nil
      self[:description] = desc
    end

    self[:architecture] = "all"

    self[:dependencies] = []
    puts "Processing dependencies:"
    pom["dependencies"][0]["dependency"].each do | dep |
      dep_artifact_id, dep_version, dep_scope = dep["artifactId"].to_s, dep["version"].to_s, dep["scope"]
      print "  "
      print dep["artifactId"]
      print ":"
      print dep["version"]
      print ":"
      print dep["scope"]
      puts
      if dep_scope != "test" 
        self[:dependencies] << "#{libjava_name(dep_artifact_id)} =#{dep_version}"
      end
    end

    # TODO: extract further field from POM
    #lisences = pom["licenses"]
    #if lisenses != null
    #  self[:license] = "foo"
    #end

    #self[:category] = 
    #self[:vendor] = 
  end

  def libjava_name(artifact_id) 
     name = artifact_id.gsub("_", "-")
    "lib#{name}-java"
  end

  def make_tarball!(tar_path, builddir)
    pomfile = paths.first
    pom = XmlSimple.xml_in(pomfile)
   
    # create dir and store jar
    javalibdir = "#{builddir}/tarbuild/usr/share/java/"
    ::FileUtils.mkdir_p(javalibdir)
    jarfile = pomfile.gsub(".pom", ".jar")
    if !File.exists?(jarfile)
      raise "Can not find '#{jarfile}' next to pom."
    end 
    ::FileUtils.cp(jarfile, javalibdir)

    # create link to jar without version
    jar_name = File.basename(jarfile) 
    link_name = javalibdir + "/" + jar_name.gsub(/-(\d\.?)+\.jar/,".jar")
    print "Creating symlink '#{link_name}' to '#{jar_name}'"
    puts
    ::FileUtils.ln_s(jar_name, link_name)

    # package as tar
    ::Dir.chdir("#{builddir}/tarbuild") do
      tar(tar_path, ".")
    end

    safesystem(*["gzip", "-f", tar_path])
  end

end # class FPM::Source::Pom
