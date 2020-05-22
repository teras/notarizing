import parsecfg, plists, argparse, sets
import sendtoapple, sign, helper

const NOTARIZE_APP_PASSWORD = "NOTARIZE_APP_PASSWORD"
const NOTARIZE_USER         = "NOTARIZE_USER"
const NOTARIZE_ASC_PROVIDER = "NOTARIZE_ASC_PROVIDER"
const NOTARIZE_SIGN_ID      = "NOTARIZE_SIGN_ID"

const VERSION {.strdefine.}: string = ""

const p = newParser("notarizing " & VERSION):
    help("Notarize and sign DMG files for the Apple store, to make later versions of macOS happy. For more info check https://github.com/teras/notarizing")
    option("-k", "--keyfile", help="The location of a configuration file that keys are stored.")
    command("sign"):
        option("-t", "--target", help="The location of the target file (DMG or Application.app). When missing the system will scan the directory tree below this point")
        option("-i", "--signid", help="The sign id, as given by `security find-identity -v -p codesigning`")
        option("-x", "--allowedext", multiple=true, help="Allow this file extension as an executable, along the default ones. Could be used more than once")
        option("-e", "--entitlements", help="Use the provided file as entitlements")
        run:
            let config = if opts.parentOpts.keyfile != "" and opts.parentOpts.keyfile.fileExists: loadConfig(opts.parentOpts.keyfile) else: newConfig()
            let signid = if opts.signid != "" : opts.signid else: getEnv(NOTARIZE_SIGN_ID, config.getSectionValue("", NOTARIZE_SIGN_ID))
            if signid == "": quit("No sign id provided")
            var target = findApp(if opts.target != "": opts.target else: getCurrentDir())
            if target == "": target = findDmg(if opts.target != "": opts.target else: getCurrentDir())
            if target == "": quit("No target file provided")
            if opts.entitlements != "" and not opts.entitlements.fileExists: quit("Required entitlemens file " & opts.entitlements & " does not exist")
            sign(target, signid, opts.entitlements, opts.allowedext.toHashSet)
            quit()
    command("send"):
        option("-t", "--target", help="The location of the DMG file. When missing the system will scan the directory tree below this point")
        option("-b", "--bundleid", help="The required BundleID. When missing, the system guess from existing PList files inside an .app folder")
        option("-p", "--password", help="The Apple password")
        option("-u", "--user", help="The Apple username")
        option("-a", "--ascprovider", help="The specific associated provider for the current Apple developer account")
        run:
            let config = if opts.parentOpts.keyfile != "" and opts.parentOpts.keyfile.fileExists: loadConfig(opts.parentOpts.keyfile) else: newConfig()
            let password = if opts.password != "": opts.password else: getEnv(NOTARIZE_APP_PASSWORD, config.getSectionValue("",NOTARIZE_APP_PASSWORD))
            if password == "": quit("No password provided")
            let user = if opts.user != "": opts.user else: getEnv(NOTARIZE_USER, config.getSectionValue("", NOTARIZE_USER))
            if user == "": quit("No user provided")
            let plist = findPlist(if opts.target != "": opts.target else: getCurrentDir())
            let bundleId = if opts.bundleid != "": opts.bundleid else: loadPlist(plist).getOrDefault("CFBundleIdentifier").getStr("")
            if bundleId == "": quit("No Bundle ID provided")
            let dmg = findDmg(if opts.target != "": opts.target else: getCurrentDir())
            if dmg == "": quit("No target file provided")
            let asc_provider = if opts.ascprovider != "": opts.ascprovider else: getEnv(NOTARIZE_ASC_PROVIDER, config.getSectionValue("", NOTARIZE_ASC_PROVIDER))
            sendToApple(bundleId, dmg, user, password, asc_provider)
            quit()
p.run(commandLineParams())
stdout.write(p.help)
quit(1)
