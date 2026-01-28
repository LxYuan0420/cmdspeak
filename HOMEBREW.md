# Homebrew Distribution Setup

## Creating the Homebrew Tap

To distribute CmdSpeak via Homebrew, create a separate repository:

### 1. Create the tap repository

Create a new GitHub repository named `homebrew-cmdspeak` at:
`https://github.com/LxYuan0420/homebrew-cmdspeak`

### 2. Copy the formula

Copy `Formula/cmdspeak.rb` to the new repository:

```bash
# Clone the new tap repo
git clone https://github.com/LxYuan0420/homebrew-cmdspeak.git
cd homebrew-cmdspeak

# Create Formula directory and copy
mkdir -p Formula
cp /path/to/cmdspeak/Formula/cmdspeak.rb Formula/

# Commit and push
git add .
git commit -m "Add cmdspeak formula"
git push
```

### 3. Create a release tag

In the main cmdspeak repository, create a version tag:

```bash
cd /path/to/cmdspeak
git tag -a v0.1.0 -m "Release v0.1.0"
git push origin v0.1.0
```

### 4. Test the installation

```bash
# Add the tap
brew tap LxYuan0420/cmdspeak

# Install
brew install cmdspeak

# Verify
cmdspeak --version
```

## Updating the Formula

When releasing a new version:

1. Update `version` in `Sources/CmdSpeak/Core/CmdSpeakCore.swift`
2. Create a new git tag: `git tag -a vX.Y.Z -m "Release vX.Y.Z"`
3. Push the tag: `git push origin vX.Y.Z`
4. Update the formula in homebrew-cmdspeak with the new tag

## Alternative: HEAD-only Installation

For users who want the latest development version:

```bash
brew install --HEAD LxYuan0420/cmdspeak/cmdspeak
```

This uses the `head` clause in the formula to build from main branch.
