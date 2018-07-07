pragma solidity ^0.4.8;
        
contract Owned {
     address public owner;

    modifier only_owner() {
        if (msg.sender == owner) {
            _;
        }
    }
    
    event OwnerChanged(address oldOwner,address newOwner);

    constructor () public {
        owner = msg.sender;
    }

    function changeOwner(address _newOwner) external only_owner {
        address oldOwner = owner;
        owner = _newOwner;
        emit OwnerChanged(oldOwner,_newOwner);
    }
} 

contract tokenRecipient { function receiveApproval(address _from, uint256 _value, address _token, bytes _extraData) public ; }  

contract LandShares {
    /* Public variables of the token */
    string public standard = 'Token 1.0';           //ERC20 once we have a token symbol
    string public name = 'LandShares token';        // we will migrate to Qi
    string public symbol = 'LST';
    uint8 public decimals;
    uint256 public totalSupply;
    
    address internal depositHoldingAddress = 0x1945;
    uint256 internal lastAgreementNo = 0;

    struct agreement {
        address farmer;
        address landowner;
        address retailer;
        string considerationDueFarmer;              //description of land / lease
        string considerationDueRetailer;            //description of what retailer should receive (and where / how)
        uint8 valueOffered;
        bool leaseCompletedSuccessfully;
        bool retailerReceivedConsideration;
        uint8 depositRequired;
        uint8 depositMade;
        uint8 latestCancellationDate;               //will be a block number
        uint8 completionDate;                       //will be a block number
    }

    /* This creates an array with all balances */
    mapping (address => uint256) public balanceOf;
    mapping (address => mapping (address => uint256)) public allowance;
    mapping (uint256 => agreement) public agreements;


    /*  */
    event AgreementMade(
        address indexed retailer, address indexed landowner, address indexed farmer, 
        uint8 depositMade, string considerationDueFarmer, string considerationDueRetailer);
    
    /*  */
    event AgreementCompleted(
        address indexed retailer, address indexed landowner, address indexed farmer, 
        uint8 agreementValue, string considerationDueRetailer);
    
    /*  */
    event AgreementCancelledByAdmin(
        address admin, address indexed retailer, address indexed landowner, address indexed farmer, 
        uint8 agreementValue,  string considerationDueFarmer, string considerationDueRetailer);
    
    /* This generates a public event on the blockchain that will notify clients */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /* This notifies clients about the amount burnt */
    event Burn(address indexed from, uint256 value);
    
    

    /* Initializes contract with initial supply tokens to the creator of the contract */
    constructor (
            uint256 initialSupply,
            string tokenName,
            uint8 decimalUnits,
            string tokenSymbol
        ) public  {
            balanceOf[msg.sender] = initialSupply;              // Give the creator all initial tokens
            totalSupply = initialSupply;                        // Update total supply
            name = tokenName;                                   // Set the name for display purposes
            symbol = tokenSymbol;                               // Set the symbol for display purposes
            decimals = decimalUnits;                            // Amount of decimals for display purposes
    }

    /* A retailer may offer an agreement, specifying a given consideration to receive from the farmer, a total price the
      retailer will pay, and a deposit which the landowner should pay to secure non-abuse of the lease*/
    /* Eventually, the UN will be able to (re)/set the appropriate deposit, based on knowledge of industry/ country
      gained from details specified in considerationDueRetailer */
    function offerAgreement ( 
            string considerationDueRetailer, 
            uint8 valueOffered,
            uint8 depositRequired,
            uint8 completionDate,
            uint8 latestCancellationDate
        ) public returns (uint256 agreeementRefNo) {
        
        require (valueOffered > 0);  
        
        agreement memory offer;
        offer.considerationDueRetailer = considerationDueRetailer;
        offer.valueOffered = valueOffered;
        offer.completionDate = completionDate;
        offer.latestCancellationDate = latestCancellationDate;
        if (depositRequired > 0) 
            offer.depositRequired = depositRequired;
        offer.depositMade = 0;

        lastAgreementNo++;
        agreements[lastAgreementNo] = offer;
        return lastAgreementNo;
    }
    
    
    /* A landowner may place a deposit on an offered agreement, reserving it. This will have to be arranged off-chain with the retailer,
      first-come first served wont work! */
    /* If the retailer did not set a cancellation date, then the landowner may */
    function landownerAcceptAgreement ( 
            uint256 agreementRefNo,
            string considerationDueFarmer, 
            uint8 latestCancellationDate
        ) public returns (uint256 refNo) {
        
        agreement memory offer = agreements[agreementRefNo];
        require (balanceOf[msg.sender] >= offer.depositRequired);           // Check if the sender has enough
        require (offer.depositMade == 0);                                   // Check that no-one has already accepted the agreement
        
        offer.landowner = msg.sender;
        offer.considerationDueFarmer = considerationDueFarmer;
        if (latestCancellationDate != 0)
            offer.latestCancellationDate = latestCancellationDate;
        transfer (depositHoldingAddress, offer.depositRequired);  
        offer.depositMade =  offer.depositRequired; 
        agreements[agreementRefNo] = offer;
        return agreementRefNo;
    }

    /* A landowner can back out before the farmer has signed up, as long as it's not past any cancellation date that was set.
      If the retailer wants to cancel, it needs to contact the landowner off-chain to ask them to cancel */
    /* Later will need admin functionality so that UN can cancel agreement as well */
    function landownerCancelAgreement (
            uint256 agreementRefNo
        ) public returns (bool success)  {
        
        agreement memory offer = agreements[agreementRefNo];
        require (offer.landowner == msg.sender);
        require (offer.depositMade > 0);
        require (offer.latestCancellationDate == 0 || offer.latestCancellationDate >= block.number);
        
        refundDeposit (msg.sender, offer.depositRequired);  
        agreements[agreementRefNo].depositMade = 0;
        agreements[agreementRefNo].landowner = 0x0;
        return true;
    }

    /* A farmer can accept any agreement he can find. There is currently no protection from abuse by farmers */
    /* Once the farmer accepts an agreement, it is set in stone until its completion date */
    function farmerAcceptsAgreement (
            uint256 agreementRefNo
        ) public returns (uint256 refNo)  {
        
        agreement memory offer = agreements[agreementRefNo];
        require (offer.depositMade > 0);                                 // Check that some landowner has accepted the agreement
        require (offer.farmer == 0x0);                                   // Check that no farmer has accepted the agreement
        
        offer.farmer = msg.sender;
        agreements[agreementRefNo] = offer;
        
        emit AgreementMade(offer.retailer, offer.landowner, offer.farmer,
            offer.depositMade, offer.considerationDueFarmer, offer.considerationDueRetailer);
        return agreementRefNo;
    }
    
    /* Retailer accepts that the farmer has delivered what is required by the agreement. 
      Currently, this closes out the agreement and everyone gets paid. */
    function retailerCompleteAgreement (
            uint256 agreementRefNo
        ) public returns (bool success)  {
        
        agreement memory offer = agreements[agreementRefNo];
        require (offer.retailer == msg.sender);
        require (offer.farmer != 0x0);                                   // Check that some farmer has accepted the agreement
        
        transfer (offer.farmer, (offer.valueOffered * 7/10)); 
        refundDeposit (offer.landowner, offer.depositMade);  
        agreements[agreementRefNo].depositMade = 0;
        transfer (offer.landowner, offer.valueOffered * 3/10); 
        delete agreements[agreementRefNo];
        
        emit AgreementCompleted(offer.retailer, offer.landowner, offer.farmer, offer.valueOffered, offer.considerationDueRetailer);
        return true;
    }

    /* If retailer did not close out agreement, ie farmer did not deliver, but the landowner DID deliver,
      the farmer can accept that the lease was delivered and return landowner the deposit */
    /* only possible after lease completion date */
    function farmerCompleteAgreement (
            uint256 agreementRefNo
        ) public returns (bool success)  {
            
        agreement memory offer = agreements[agreementRefNo];
        require (offer.farmer == msg.sender);
        require (block.number >= offer.completionDate);        
     
        agreements[agreementRefNo].leaseCompletedSuccessfully = true;
        refundDeposit (offer.landowner, offer.depositMade);  
        
        return true;
         
    }
    
    /* Send coins */
    function transfer(address _to, uint256 _value) public {
        require (_to != 0x0);                               // Prevent transfer to 0x0 address. Use burn() instead
        require (balanceOf[msg.sender] >= _value);           // Check if the sender has enough
        require (balanceOf[_to] + _value >= balanceOf[_to]); // Check for overflows
        balanceOf[msg.sender] -= _value;                     // Subtract from the sender
        balanceOf[_to] += _value;                            // Add the same to the recipient
        emit Transfer(msg.sender, _to, _value);                   // Notify anyone listening that this transfer took place
    }
    
    
    /* Refund from our deposit 'address' to msg.sender */
    function refundDeposit(address _to, uint256 _value) private {
        require (_to != 0x0);                                   // Prevent transfer to 0x0 address. Use burn() instead
        require (balanceOf[depositHoldingAddress] >= _value);   // Check if the sender has enough
        require (balanceOf[_to] + _value >= balanceOf[_to]);    // Check for overflows
        balanceOf[depositHoldingAddress] -= _value;             // Subtract from the sender
        balanceOf[_to] += _value;                               // Add the same to the recipient
        emit Transfer(depositHoldingAddress, _to, _value);      // Notify anyone listening that this transfer took place
    }
    

    /* Allow another contract to spend some tokens in your behalf */
    function approve(address _spender, uint256 _value) public returns (bool success) {
        allowance[msg.sender][_spender] = _value;
        return true;
    }

    /* Approve and then communicate the approved contract in a single tx */
    function approveAndCall(address _spender, uint256 _value, bytes _extraData) public returns (bool success) {
        tokenRecipient spender = tokenRecipient(_spender);
        if (approve(_spender, _value)) {
            spender.receiveApproval(msg.sender, _value, this, _extraData);
            return true;
        }
    }        

    /* A contract attempts to get the coins */
    function transferFrom(address _from, address _to, uint256 _value) public returns (bool success) {
        require (_to != 0x0);                                // Prevent transfer to 0x0 address. Use burn() instead
        require (balanceOf[_from] >= _value);                 // Check if the sender has enough
        require (balanceOf[_to] + _value >= balanceOf[_to]);  // Check for overflows
        require (_value <= allowance[_from][msg.sender]);     // Check allowance
        balanceOf[_from] -= _value;                           // Subtract from the sender
        balanceOf[_to] += _value;                             // Add the same to the recipient
   

        allowance[_from][msg.sender] -= _value;
        emit Transfer(_from, _to, _value);
        return true;
    }
    
    function burn(uint256 _value) public returns (bool success) {
        require (balanceOf[msg.sender] >= _value);            // Check if the sender has enough
        balanceOf[msg.sender] -= _value;                      // Subtract from the sender
        totalSupply -= _value;                                // Updates totalSupply
        emit Burn(msg.sender, _value);
        return true;
    }


        // burnFrom currently relies on visibility internal.
        // we need to set up an administrators register and require administrator contains [msg.sender]
    function burnFrom(address _from, uint256 _value) internal returns (bool success) {
        require (balanceOf[_from] >= _value);                // Check if the sender has enough
        require (_value <= allowance[_from][msg.sender]);    // Check allowance
        balanceOf[_from] -= _value;                          // Subtract from the sender
        totalSupply -= _value;                               // Updates totalSupply
        emit Burn(_from, _value);
        return true;
    }
}
