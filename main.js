if (web3)
  console.log('Using',web3.MetamaskInpageProvider);
else
  console.log('Uh oh! no web3 :(');

var baseTx = {
  from: web3.eth.accounts[0],
  gasPrice: "9000000000",
  gas: "85000",
  to: '0x30eff105dc230b908e87d2932851a733df3e34dc',
  value: 1234567,
  data: ""
};

console.log('running');

doAnyTx = (id)=> {
  const tx = Object.assign ({}, baseTx);
  console.log('Accepted: ',id);
  if (id)
    tx.data = id;
  web3.eth.sendTransaction(tx, (err, transactionHash) => {console.log('done:')});
}

// doAnyTx()
