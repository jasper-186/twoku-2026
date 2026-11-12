![Splash](https://i.imgur.com/LXhqf4J.png)

![Overview](https://i.imgur.com/zcRYrNe.jpg)

# 🔮 Twoku (for Roku)
An Improvable™ Twitch app for Roku. Still buggy, so feel free to suggest improvements (and code and features). Unfortunately, the code is very disorganized and messy because the original developers knew nothing about Roku development when they started on this.

Also, the original devs have not been very active with this project recently. So if you can contribute, please do. There are still many desirable features that have not been added (just go on the Discord).

## Discord
If you have any questions or comments (or phishing links):

[![Discord](https://discordapp.com/api/guilds/721488568303878155/widget.png?style=banner2)](https://discord.gg/kV5SXkZ)

## Support
If you would like to support Twoku:

 [![Support with PayPal](https://www.paypalobjects.com/en_US/i/btn/btn_donateCC_LG.gif)](https://www.paypal.com/cgi-bin/webscr?cmd=_donations&business=YRPQDG5UY26DS&currency_code=CAD&source=url)

## Contributing
If you have an idea (feature, etc.) that you would like to contribute (with code) to the project with, DM one of the developers on the Discord with your idea. Otherwise, if you just have an idea, post it in the ```#features``` channel on the Discord server. You can also just fork this repository as its up to date and implement the feature yourself.

## How to Install

**This build is not published as a Roku channel**, so it cannot be installed
from the channel store or with an access code. It is distributed as a zip file
and has to be sideloaded onto a Roku in developer mode.

### Manual Developer Install
1. [Enable developer mode for Roku](https://blog.roku.com/developer/developer-setup-guide) — this is required, because the published package is **not signed**.
2. Log into your Roku from your browser using IP from previous step (http://192.168.x.x)
3. Download the latest `twoku-<version>.zip` from the [GitHub Releases page](../README.md#continuous-integration). (You can also build it yourself — see [Build / Run / Deploy](AGENTS.md#build--run--deploy) — but do not include extra top level directories in the ZIP file, otherwise you may get the error: "```Install Failure: No manifest. Invalid package.```".)
4. Upload the ZIP file in Roku Development Application Installer (step 2)
5. Press Install
6. Twoku should now be installed on your Roku. You should see it at the end of your channel list, under the name **Twoku-2026**

### A note on the old access codes

The access codes `TWOKU`, `TTWOKU` and `C6ZVZD` refer to the separately
published *Twoku* channel, which is a different build with its own release
history. They install that channel, **not** this repository's build. The first
two stopped working in February 2022 when Roku shut down private channels.

## Supported Features
* Browsing live channels and categories by viewer count (press down to load more)
* Search (with buggy auto-complete)
* Viewing followed live streamers
* Viewing popular clips from the past 7 days for each category
* Chat (only for live streams)
* VODs (except subscriber-only)

## Notable Unsupported Features
* All clip functionality not mentioned
* Chat (for VODs)
* Subscriber-only VODs
* Everything else not mentioned
