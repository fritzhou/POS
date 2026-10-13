# Source this file in the prepared Linux cloud environment.
# Installed tools and caches live outside the application checkout.
export NEXAPOS_TOOLCHAIN_ROOT="${NEXAPOS_TOOLCHAIN_ROOT:-/workspace/.toolchains}"
export PUB_CACHE="$NEXAPOS_TOOLCHAIN_ROOT/pub-cache"
export XDG_CONFIG_HOME="$NEXAPOS_TOOLCHAIN_ROOT/config"
export FLUTTER_SUPPRESS_ANALYTICS=true
if [ -x "$NEXAPOS_TOOLCHAIN_ROOT/deno/deno" ]; then
  export PATH="$NEXAPOS_TOOLCHAIN_ROOT/deno:$PATH"
fi
mkdir -p "$PUB_CACHE" "$XDG_CONFIG_HOME"
if [ -d "$NEXAPOS_TOOLCHAIN_ROOT/flutter/bin" ]; then
  export PATH="$NEXAPOS_TOOLCHAIN_ROOT/flutter/bin:$PATH"
fi
if [ -x "$NEXAPOS_TOOLCHAIN_ROOT/jdk/bin/java" ]; then
  export JAVA_HOME="$NEXAPOS_TOOLCHAIN_ROOT/jdk"
  export PATH="$JAVA_HOME/bin:$PATH"
fi
if [ -d "$NEXAPOS_TOOLCHAIN_ROOT/android-sdk" ]; then
  export ANDROID_HOME="$NEXAPOS_TOOLCHAIN_ROOT/android-sdk"
  export ANDROID_SDK_ROOT="$ANDROID_HOME"
  export ANDROID_USER_HOME="$XDG_CONFIG_HOME/android"
  export GRADLE_USER_HOME="$NEXAPOS_TOOLCHAIN_ROOT/gradle-cache"
  mkdir -p "$ANDROID_USER_HOME" "$GRADLE_USER_HOME" "$XDG_CONFIG_HOME/java" "$XDG_CONFIG_HOME/java-prefs"
  export JAVA_OPTS="${JAVA_OPTS:+$JAVA_OPTS }-Duser.home=$XDG_CONFIG_HOME/java -Djava.util.prefs.userRoot=$XDG_CONFIG_HOME/java-prefs"
  export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"
fi
