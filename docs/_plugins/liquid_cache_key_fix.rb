# Workaround for an upstream Jekyll bug (present in 4.3.x and 4.4.x, still on
# Jekyll master as of September 2026):
#
# LiquidRenderer.normalize_path strips everything up to the last "/lib"
# path segment (via its gems-matching branch), so site pages such as
# features/library.html, pt/features/library.html and es/features/library.html
# all normalize to the same cache key. The parsed-template cache then serves
# whichever language renders first for all three URLs.
#
# Returning the filename unchanged keeps every key unique. The only downside
# is less pretty profiling labels for gem paths, which this site never reads.
#
# GitHub Pages builds with Jekyll 3.10, which lacks this code path entirely,
# so production was never affected. Pages also ignores _plugins in safe mode,
# so this file only changes local 4.x builds.
require "jekyll"

module Jekyll
  class LiquidRenderer
    private

    def normalize_path(filename)
      filename.to_s
    end
  end
end
