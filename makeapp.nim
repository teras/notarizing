import parsecfg, plists, argparse, sets, strutils, types
import sendtoapple, sign, helper, myexec, package, autos, java

const NOTARIZE_APP_PASSWORD = "NOTARIZE_APP_PASSWORD"
const NOTARIZE_USER         = "NOTARIZE_USER"
const NOTARIZE_ASC_PROVIDER = "NOTARIZE_ASC_PROVIDER"
const NOTARIZE_SIGN_ID      = "NOTARIZE_SIGN_ID"
const SIGN_P12_PASS         = "SIGN_P12_PASS"
const SIGN_GPG_PASS         = "SIGN_GPG_PASS"

const VERSION {.strdefine.}: string = ""

template commonOutOpt() = option("-o", "--output", help="The output directory")
template commonOutImp(useCurrentDir=true) =
  let output {.inject.} = if opts.output == "": (if useCurrentDir: getCurrentDir() else:"") else: opts.output.absolutePath

template keyfileOpt() = option("--keyfile", help="The location of a configuration file that keys are stored.")
template keyfileImp() =
  let keyfile {.inject.} = opts.keyfile

template ostypeOpt() = option("--os", help="Comma separated list of possible operating system targets (defaults to \"system\", which is current system package): " & typesList())
template ostypeImp(single:bool) =
  let os {.inject.} = findOS(opts.os)
  if single and os.len>1: kill "Only one OS is supported for this mode"

template allOpt() =
  flag("-v", "--verbose", multiple=true, help="Be more verbose when signing files. 0=quiet and only errors, 1=show output, 2=show output and command, 3=show everything including passwords")
  flag("--keeponerror", help="Keep temporary files when commands fail to execute. This option is useful for debugging purposes")
template allImp() =
  VERBOCITY = opts.verbose
  KEEPONERROR = opts.keeponerror

template resOpt() = option("--res", help="The location of the resources files, needed when the application is built.")
template nameresImp() =
  let
    name {.inject.} = checkParam(opts.name.strip, "No application name provided")
    res {.inject.} = when compiles(opts.res):
      if opts.res == "": "" else: checkParam(opts.res, "Unable to locate directory " & opts.res, asDir=true)
      else: ""
    url {.inject.} = opts.url

template infoOpt(baseonly:bool) =
  option("--name", help="The name of the application")
  if not baseonly:
    option("--version", help="The version of the application")
    option("--descr", help="Application description")
    option("--cat", help="The categories of the application")
    option("--vendor", help="The vendor of the package")
    option("--assoc", multiple=true, help="File associations with this application. Format is EXT:MIMETYPE:DESCRIPTION. Only the EXT part is required. All other parts could be missing. To provide a custom icon, under resource folder use an file named as \"EXT.icns\". Usage example: \"ass:text/x-ssa:ASS Subtitle file\"")
  option("--url", help="Product URL")
template infoImp(res:string) =
  let
    version {.inject.} = if opts.version == "" : "1.0" else: opts.version
    descr {.inject.} = if opts.descr == "" : opts.name else: opts.descr
    assoc {.inject.} = findAccociations(opts.assoc, res)
    vendor {.inject.} = if opts.vendor == "": findUsername().capitalizeAscii else: opts.vendor
    cat {.inject.} = opts.cat

template javaOpt() =
  option("--appdir", help="The directory where the application itself is stored")
  option("--jar", help="The desired entry JAR")
  resOpt()
  option("--extra", help="The location of extra files to added to the bundle. This is a hierarchical folder, where first level has the name of the target (as defined by system target) or special keywords \"windows\" for all Windows targets and \"common\" for all targets. Second level are all files that will be merged with the files located at appdir.")
  option("--modules", help="Comma separated list of required modules. Defaults to \"java.datatransfer,java.desktop,java.logging,java.prefs,java.rmi,java.xml,jdk.charsets\"")
  option("--jvmopt", multiple=true, help="JVM option. Could be used more than once. If DEFAULTS are given, then the options \"-Dawt.useSystemAAFontSettings=on\" and \"-Dswing.aatext=true\" are added")
  option("--id", help="Reverse URL unique identifier")
  option("--jdk", help="The location of the JDK")
template javaImp(name:string) =
  let
    appdir {.inject.} = checkParam(opts.appdir, "No application directory provided", asDir=true).absolutePath.normalizedPath
    jar {.inject.} = getJar(opts.jar, appdir)
    extra {.inject.} = opts.extra
    modules {.inject.} = if opts.modules == "" : "java.datatransfer,java.desktop,java.logging,java.prefs,java.rmi,java.xml,jdk.charsets" else: opts.modules
    jvmopts {.inject.} = getJvmOpts(opts.jvmopt)
    id {.inject.} = if opts.id == "": constructId(findUsername(), name) else: opts.id
    jdk {.inject.} = opts.jdk

template signOpt() =
  option("--signid", help="The sign id, as given by `security find-identity -v -p codesigning`. [MacOS target]")
  option("--entitle", help="Use the provided file as entitlements, defaults to a generic entitlements file. [MacOS target]")
  option("--p12file", help="The p12 file containing the signing keys. [Windows target]")
  option("--p12pass", help="The password of the p12file. [Windows target]")
  option("--gpgdir", help="The GnuPG directory containing the signing keys. [Linux target]")
  option("--gpgpass", help="The password of the GnuPG file. [Windows target]")
template signImp(sign:bool, keyfile:string) =
  if sign:
    let config = if keyfile != "" and keyfile.fileExists: loadConfig(keyfile) else: newConfig()
    ID = config.checkPass(opts.signid, NOTARIZE_SIGN_ID, "No sign id provided", os, @[pMacos])
    P12PASS = config.checkPass(opts.p12pass, SIGN_P12_PASS, "No p12 password provided", os, windowsTargets)
    GPGPASS = config.checkPass(opts.gpgpass, SIGN_GPG_PASS, "No GnuPG password provided", os, linuxTargets)
  let entitle {.inject.} = if not sign: "" else: checkParam(if opts.entitle == "": getDefaultEntitlementFile() else: opts.entitle.absolutePath.normalizedPath, "Required entitlements file " & opts.entitle & " does not exist")
  let p12file {.inject.} = opts.p12file
  let gpgdir {.inject.} = opts.gpgdir
  if sign:
    if os.contains(windowsTargets):
      if p12file=="": kill "No p12 file provided"
      elif not p12file.fileExists: kill "No p12 file " & p12file & " exists"
    if os.contains(linuxTargets):
      if gpgdir=="": kill "No GnuPG directory provided"
      elif not gpgdir.dirExists: kill "No GnuPG directory " & p12file & " exists"

template sendOpt() =
  option("--password", help="The Apple password")
  option("--user", help="The Apple username")
  option("--ascprovider", help="The specific associated provider for the current Apple developer account")
template sendImp(strict:bool) =
  let config = if keyfile != "" and keyfile.fileExists: loadConfig(keyfile) else: newConfig()
  let ascprovider {.inject.} = if opts.ascprovider != "": opts.ascprovider else: getEnv(NOTARIZE_ASC_PROVIDER, config.getSectionValue("", NOTARIZE_ASC_PROVIDER))
  PASSWORD = if opts.password != "": opts.password else: getEnv(NOTARIZE_APP_PASSWORD, config.getSectionValue("",NOTARIZE_APP_PASSWORD))
  USER = if opts.user != "": opts.user else: getEnv(NOTARIZE_USER, config.getSectionValue("", NOTARIZE_USER))
  if strict:
    checkParam PASSWORD, "No password provided"
    checkParam USER, "No user provided"


const p = newParser("makeapp " & VERSION):
  help("Create, sign, and notarize DMG files for the Apple store, to make later versions of macOS happy.\nMore info at https://github.com/teras/makeapp")
  command("help"):
    run:
      echo """
Environmental variables:
  macOS:
    NOTARIZE_APP_PASSWORD : The notarizing password of the current user
    NOTARIZE_USER         : The notarizing user
    NOTARIZE_ASC_PROVIDER : Notarizing asc. provider
    NOTARIZE_SIGN_ID      : The ID of the user which will be used to sing the application 
  Windows:
    SIGN_P12_PASS         : The password of the p12 file
  Linux:
    SIGN_GPG_PASS         : The password of the GnuPG file

Default resources:
  macOS specific: 
    app.icns         : The application icon
    dmg_template.zip : The application DMG template
    [ASSOC].icns     : The file association icons for file extensions ASSOC. E.g. for an association of ".txt" files, the filename should be "txt.icns"

  Windows specific:
    app.ico          : The application icon
    install.ico      : The installer icon
    logo-install.bmp : The logo to display on the left of the installer
    logo-install-small.bmp
    logo-install-small.bmp
                     : The small icon to display on the installer
    [ASSOC].ico      : The file association icons for file extensions ASSOC. E.g. for an association of ".txt" files, the filename should be "txt.ico"

  Linux specific:
    app.png          : The application icon

Extras folder organization:
    extras
    ├── common
    ├── linux32
    ├── linux64
    ├── linux
    ├── win32
    ├── win64
    ├── windows
    └── macos
     
      """
      exit(true)
  command("create"):
    commonOutOpt()
    infoOpt(false)
    javaOpt()
    option("--notarize", help="Notarize DMG application after creation, boolean value. Defaults to false")
    option("--instoutput", help="The output location of the installer files. Defaults to the same as --output")
    signOpt()
    sendOpt()
    keyfileOpt()
    ostypeOpt()
    allOpt()
    run:
      commonOutImp()
      nameresImp()
      infoImp(res)
      javaImp(name)
      keyfileImp()
      ostypeImp(false)
      signImp(true, keyfile)
      let notarize = opts.notarize.isTrue
      let instoutput = if opts.instoutput == "": output else: opts.instoutput
      sendImp(notarize)
      allImp()
      safedo: makeJava(os, output, res, name, version, appdir, jar, modules, jvmopts, assoc, extra, vendor, descr, id, url, jdk)
      safedo: createPack(os, "", instoutput, output, true, entitle, p12file, gpgdir, res, name, version, descr, url, vendor, cat, assoc)
      if notarize:
        safedo: sendToApple(id, instoutput / name & "-" & version & ".dmg", ascprovider)
      exit()
  command("java"):
    commonOutOpt()
    infoOpt(false)
    javaOpt()
    ostypeOpt()
    allOpt()
    run:
      commonOutImp()
      nameresImp()
      javaImp(name)
      infoImp(res)
      ostypeImp(false)
      allImp()
      safedo: makeJava(os, output, res, name, version, appdir, jar, modules, jvmopts, assoc, extra, vendor, descr, id, url, jdk)
      exit()
  command("pack"):
    commonOutOpt()
    infoOpt(false)
    resOpt()
    signOpt()
    option("--templ", help="The location of the template (e.g. DMG under macOS, Inno setup under Windows)")
    option("--target", help="The location of the application. When missing the system will try to scan the directory tree below this point")
    flag("--nosign", help="Skp sign procedure")
    keyfileOpt()
    ostypeOpt()
    allOpt()
    run:
      commonOutImp(false)
      nameresImp()
      infoImp(res)
      keyfileImp()
      let templ = checkParam(opts.templ, "No template found", asFile=true)
      let sign = not opts.nosign
      ostypeImp(true)
      signImp(sign, keyfile)
      allImp()
      safedo: createPack(os, templ, output, opts.target, sign, entitle, p12file, gpgdir, res, name, version, descr, url, vendor, cat, assoc)
      exit()
  command("sign"):
    option("-t", "--target", help="The location of the target file (DMG or Application.app). When missing the system will scan the directory tree below this point")
    signOpt()
    infoOpt(true)
    keyfileOpt()
    ostypeOpt()
    allOpt()
    run:
      keyfileImp()
      ostypeImp(true)
      nameresImp()
      signImp(true, keyfile)
      allImp()
      if os.contains(linuxTargets): kill "Signing on Linux is not supported; signing is supported only when packaging"
      safedo: sign(os, opts.target, entitle, p12file, name, url)
      exit()
  when system.hostOS == "macosx":
    command("notarize"):
      sendOpt()
      option("--id", help="Reverse URL unique identifier. When missing, the system guess from existing PList files inside an .app folder")
      option("-t", "--target", help="The location of the DMG/ZIP file. When missing the system will scan the directory tree below this point")
      keyfileOpt()
      allOpt()
      run:
        keyfileImp()
        sendImp(true)
        allImp()
        let target = if opts.target != "": opts.target else: getCurrentDir()
        let id = checkParam(if opts.id != "": opts.id else: loadPlist(findPlist(target)).getOrDefault("CFBundleIdentifier").getStr(""), "No Bundle ID provided")
        var fileToSend = findDmg(target)
        if fileToSend == "": fileToSend = findZip(target)
        if fileToSend == "":kill("No target file found")
        safedo: sendToApple(id, fileToSend, ascprovider)
        exit()
p.run(commandLineParams())
stdout.write(p.help)
kill("No options given")
