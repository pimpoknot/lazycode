# Template: the release workflow fills in the values and publishes it to the tap.
class Lazycode < Formula
  desc "Lightweight IDE with the power and look of LazyVim"
  homepage "https://github.com/@OWNER@/lazycode"
  url "https://github.com/@OWNER@/lazycode/releases/download/v@VERSION@/lazycode-@VERSION@.tar.gz"
  version "@VERSION@"
  sha256 "@SHA256@"
  license "Apache-2.0"

  depends_on "git"

  def install
    libexec.install Dir["*"], ".lazycode"
    chmod 0755, libexec/"bin/lazycode"
    chmod 0755, libexec/"install.sh"
    bin.install_symlink libexec/"bin/lazycode"
  end

  def caveats
    <<~EOS
      The first `lazycode` run downloads its isolated runtime and plugins to your home folder.
    EOS
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/lazycode version")
  end
end
