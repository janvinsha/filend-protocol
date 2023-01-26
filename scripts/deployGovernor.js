const main = async () => {
  const governorFactory = await hre.ethers.getContractFactory("GovernorAlpha");
  const governor = await governorFactory.deploy(
    //address timelock_,
    "0x610CcBCdF0f4C39Fc067f7D9979d8Cd961815E44",
    //address fil,
    "0x507c354050923c1F1bb48A05C27Fcd9171864861",
    //address guardian_
    "0x659CE0FC2499E1Fa14d30F5CD88aD058ba490e39"
  );
  await governor.deployed();
  console.log("governor Contract deployed to:", governor.address);
};

const runMain = async () => {
  try {
    await main();
    process.exit(0);
  } catch (error) {
    console.log(error);
    process.exit(1);
  }
};

runMain();
