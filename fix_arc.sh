sed -i '' 's/\[_retainedRomData release\];//g' /Users/jayjay/gitrepos/truchiemu/TruchieEmu/Engine/LibretroBridge.mm
sed -i '' 's/\[_retainedRomPath release\];//g' /Users/jayjay/gitrepos/truchiemu/TruchieEmu/Engine/LibretroBridge.mm
sed -i '' 's/\[_saveStatePath release\];//g' /Users/jayjay/gitrepos/truchiemu/TruchieEmu/Engine/LibretroBridge.mm
sed -i '' 's/\[_audioEngine release\];//g' /Users/jayjay/gitrepos/truchiemu/TruchieEmu/Engine/LibretroBridge.mm
sed -i '' 's/\[_audioSourceNode release\];//g' /Users/jayjay/gitrepos/truchiemu/TruchieEmu/Engine/LibretroBridge.mm
sed -i '' 's/\[super dealloc\];//g' /Users/jayjay/gitrepos/truchiemu/TruchieEmu/Engine/LibretroBridge.mm
sed -i '' 's/\[newInst release\];//g' /Users/jayjay/gitrepos/truchiemu/TruchieEmu/Engine/LibretroBridge.mm
sed -i '' '/\[romPath retain\]/d' /Users/jayjay/gitrepos/truchiemu/TruchieEmu/Engine/LibretroBridge.mm
