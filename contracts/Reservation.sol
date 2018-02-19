pragma solidity ^0.4.24;


contract Reservation {

  uint64 private constant MAX_SLOTS = 10;
  uint256 private constant STORAGE_LOCATION_ARRAY = 0xDEADBEEF;
  uint256 private constant GAS_REFUNDED_PER_GASTOKEN = 29520;


  ////////////////////////////////////////////////////////////////////////////
  // Types
  ////////////////////////////////////////////////////////////////////////////

  struct Room {
    uint64 capacity;
    Slot[MAX_SLOTS] slots;
  }

  struct Slot {
    bool enabled;
    bytes16 data;
    mapping (uint64 => address) reservations;
  }

  ////////////////////////////////////////////////////////////////////////////
  // Modifiers
  ////////////////////////////////////////////////////////////////////////////

  modifier onlyOwner() {
    require(msg.sender == owner, "Sender should be owner");
    _;
  }

  modifier noEmptyRoom(uint64 _roomId) {
    require(rooms[_roomId].capacity != 0, "Room cannot be empty");
    _;
  }

  ////////////////////////////////////////////////////////////////////////////
  // Attributes
  ////////////////////////////////////////////////////////////////////////////

  /**
   * Max days in which you can book in advance
   */
  uint64 public maxDays;

  /**
   * 30 GWei
   */
  uint256 public costPerGasUnit = 30 * 10**9;

  /**
   * Available rooms
   */
  uint64[] private roomIds;
  mapping(uint64 => Room) private rooms;

  /**
   * Owner of the contract
   */
  address private owner;

  uint256 public gasTokenSupply = 0;
  uint256 public gasTokensStartIdx = STORAGE_LOCATION_ARRAY;

  ////////////////////////////////////////////////////////////////////////////
  // Events
  ////////////////////////////////////////////////////////////////////////////

  event SlotUpdated(uint64 indexed roomId, uint64 indexed slotIdx);
  event SlotReserved(uint64 indexed roomId, uint64 indexed slotIdx, address user);

  ////////////////////////////////////////////////////////////////////////////
  // Constructor
  ////////////////////////////////////////////////////////////////////////////

  /**
   * Constructor where you can set the number of days in which you can book in
   * advance.
   *
   * @param   _maxDays    Days in which you can book in advance
   */
  constructor(uint64 _maxDays) public {
    maxDays = _maxDays;
    owner = msg.sender;
  }

  ////////////////////////////////////////////////////////////////////////////
  // External admin methods
  ////////////////////////////////////////////////////////////////////////////

  /**
   * Set the numer of days in which you can book in advance.
   *
   * @param   _maxDays    Number of days in which you can book in advance
   */
  function setMaxDays(uint64 _maxDays) external onlyOwner {
    maxDays = _maxDays;
  }

  /**
   * Update room information. If the room does not exists, create a new one.
   *
   * @param   _roomId     ID of the room.
   * @param   _capacity   Capacity of the room.
   */
  function updateRoom(uint64 _roomId, uint64 _capacity) external onlyOwner {
    // If capacity == 0 the room does not exists
    if (rooms[_roomId].capacity == 0) {
      roomIds.push(_roomId);
    }

    rooms[_roomId].capacity = _capacity;
  }

  /**
   * Update multiple slots at once.
   *
   * @param   _roomId ID of the room
   * @param   _data   Data to store
   */
  function updateSlots(uint64 _roomId, bytes16[MAX_SLOTS] _data) external
      noEmptyRoom(_roomId) onlyOwner
  {
    for (uint64 i = 0; i < MAX_SLOTS; i++) {
      setSlotData(_roomId, i, _data[i]);
      if (_data[i].length > 0) {
        setSlotStatus(_roomId, i, true);
      }
    }
  }

  function reserveInternal(uint64 _roomId, uint64 _slotIdx, uint64 _reservationDay) private noEmptyRoom(_roomId) {
    uint64 currentDay = getDay(block.timestamp);
    require(
      _reservationDay >= currentDay &&
      _reservationDay <= currentDay + maxDays,
      "Invalid reservation time"
    );

    Slot storage slot = rooms[_roomId].slots[_slotIdx];
    require(slot.enabled, "Slot disabled");
    require(slot.reservations[_reservationDay] == address(0), "Already reserved");

    slot.reservations[_reservationDay] = msg.sender;

    emit SlotReserved(_roomId, _slotIdx, msg.sender);
  }

  ////////////////////////////////////////////////////////////////////////////
  // External user methods
  ////////////////////////////////////////////////////////////////////////////

  /**
   * Reserve a room if available. Fail if the given day to book is "maxDays"
   * after the current day.
   *
   * @param   _roomId       Room ID
   * @param   _slotIdx      Slot
   * @param   _time         Day to reserve in unix epoch format. Can be any
   *                        second of the day.
   */
  function reserve(uint64 _roomId, uint64 _slotIdx, uint64 _time) public
      noEmptyRoom(_roomId)
  {
    uint64 reservationDay = getDay(_time);
    reserveInternal(_roomId, _slotIdx, reservationDay);
    mintGasToken(reservationDay, _slotIdx, _roomId);
  }

  function reserveWithGasToken(uint64 _roomId, uint64 _slotIdx, uint64 _time, uint256 _gasAmount) public payable {
    uint64 reservationDay = getDay(_time);
    reserveInternal(_roomId, _slotIdx, reservationDay);
    freeStorage(_gasAmount);
  }

  /**
   * Cancel a reservation.
   *
   * @param   _roomId       Room ID
   * @param   _slotIdx      Slot
   * @param   _time         Day to reserve in unix epoch format. Can be any
   *                        second of the day.
   */
  function cancel(uint64 _roomId, uint64 _slotIdx, uint64 _time) external
      noEmptyRoom(_roomId)
  {
    uint64 reservationDay = getDay(_time);
    uint64 currentDay = getDay(block.timestamp);
    require(
      reservationDay >= currentDay &&
      reservationDay <= currentDay + maxDays,
      "Invalid time"
    );

    Slot storage slot = rooms[_roomId].slots[_slotIdx];
    require(slot.reservations[reservationDay] == msg.sender, "You must own the reservation");

    slot.reservations[reservationDay] = address(0);

    emit SlotReserved(_roomId, _slotIdx, address(0));
  }

  /**
   * List all available rooms IDs.
   *
   * @return  List of rooms IDs
   */
  function listRooms() external view returns (uint64[]) {
    return roomIds;
  }

  /**
   * Get room information. Shows the reservation status for a given timestamp.
   *
   * @param   _roomId      ID of the room.
   * @param   _time        Used to show reservation status of the room.
   * @return  capacity    Capacity of the room.
   * @return  status      Reservation status for every slot:
   *                        0: disabled | 1: available | 2: reserved
   * @return  data        Information about the slot.
   */
  function getRoom(uint64 _roomId, uint64 _time) external view noEmptyRoom(_roomId)
    returns (uint64 capacity, uint64[MAX_SLOTS] status, bytes16[MAX_SLOTS] data)
  {
    require(_time > 0, "Time cannot be zero");

    Room storage room = rooms[_roomId];
    capacity = room.capacity;

    for (uint64 i = 0; i < MAX_SLOTS; i++) {
      Slot storage slot = room.slots[i];
      data[i] = slot.data;

      if (!slot.enabled) {
        status[i] = 0;
        continue;
      }

      status[i] = slot.reservations[getDay(_time)] == address(0) ? 1 : 2;
    }

    return;
  }

  ////////////////////////////////////////////////////////////////////////////
  // Public methods
  ////////////////////////////////////////////////////////////////////////////

  /**
  * Set a slot data. Useful for store human readable information,
  * like "9:00 - 11:00".
  *
  * @param   _roomId  ID of the room
  * @param   _slotIdx Index of the slot to update
  * @param   _data    Data to store
  */
  function setSlotData(uint64 _roomId, uint64 _slotIdx, bytes16 _data) public
      noEmptyRoom(_roomId) onlyOwner
  {
    require(_slotIdx < MAX_SLOTS, "Invalid slot index");

    rooms[_roomId].slots[_slotIdx].data = _data;

    emit SlotUpdated(_roomId, _slotIdx);
  }

  /**
  * Set a slot status. Slots can be disabled to avoid further reservations.
  *
  * @param   _roomId  ID of the room
  * @param   _slotIdx Index of the slot to update
  * @param   _status  Set to false for disable reservations
  */
  function setSlotStatus(uint64 _roomId, uint64 _slotIdx, bool _status) public
      noEmptyRoom(_roomId) onlyOwner
  {
    require(_slotIdx < MAX_SLOTS, "Invalid slot index");

    rooms[_roomId].slots[_slotIdx].enabled = _status;

    emit SlotUpdated(_roomId, _slotIdx);
  }

  function freeStorage(uint256 _amount) public payable {
    uint64 currentDay = getDay(block.timestamp);
    uint64 tstamp;
    uint64 slotIdx;
    uint64 roomId;

    require(_amount <= gasTokenSupply, "Not enough gasTokens available");

    // Cost to consume _amount of gas tokens
    uint256 cost = getFreeStorageCost(_amount);

    // Check if sender has enough funds to pay for the gas tokens consummed
    require(msg.value >= cost, "Insufficient funds to pay for the gasTokens");

    // Clear memory locations in interval [l, r] for gasTokens array
    uint256 left = gasTokensStartIdx + gasTokenSupply - _amount;
    uint256 right = gasTokensStartIdx + gasTokenSupply;

    // Empty storage
    for (uint256 i = left; i < right; i++) {
      (tstamp, slotIdx, roomId) = loadPacked(i);
      require(tstamp < currentDay, "Not enough gasTokens could be freed");

      // Clear data to obtain the refund
      rooms[roomId].slots[slotIdx].reservations[tstamp] = address(0);
      assembly {
        sstore(i, 0)
      }
      gasTokensStartIdx++;
    }

    // Refund msg.sender if msg.value was too high
    if (cost < msg.value) {
      msg.sender.transfer(msg.value - cost);
    }

    gasTokenSupply -= _amount;
  }

  ////////////////////////////////////////////////////////////////////////////
  // Private methods
  ////////////////////////////////////////////////////////////////////////////

  /**
   * Get current day by dividing timestamp by 86400 (number of seconds
   * in a day).
   *
   * @param  _timestamp     Unix timestamp to get the day from.
   * @return  Current day
   */
  function getDay(uint256 _timestamp) private pure returns (uint32) {
    return uint32(_timestamp / 86400);
  }

  function mintGasToken(uint64 _timestamp, uint64 _slotIdx, uint64 _roomId) private {
    uint256 storageLocation = gasTokensStartIdx + gasTokenSupply;
    storePacked(storageLocation, _timestamp, _slotIdx, _roomId);
    gasTokenSupply++;
  }

  /**
   *    |                            uint256                              |
   *    |--- uint64 ---| |--- uint64 ---| |--- uint64 ---| |--- uint64 ---|
   * 0x 0000000000000000 0000000000000000 0000000000000000 0000000000000000
   *    |  timestamp   | |    slotId    | |    roomId    | |    unused    |
   *
   */
  function storePacked(uint256 _location, uint64 _timestamp, uint64 _slotIdx, uint64 _roomId) private {
    uint256 packed = _timestamp | shiftRight(_slotIdx, 64) | shiftRight(_roomId, 128);

    assembly {
      sstore(_location, packed)
    }
  }

  function loadPacked(uint256 _location) private view returns (uint64 tstamp, uint64 slotIdx, uint64 roomId) {
    uint256 packed;

    assembly {
      packed := sload(_location)
    }

    tstamp = uint64(packed);
    slotIdx = uint64(shiftLeft(packed, 64));
    roomId = uint64(shiftLeft(packed, 128));
  }

  function shiftRight(uint256 data, uint256 positions) private pure returns (uint256) {
    return data * 2**positions;
  }

  function shiftLeft(uint256 data, uint256 positions) private pure returns (uint256) {
    return data / 2**positions;
  }

  function getOptimalGasTokenAmount(uint256 _txGasCost) public pure returns (uint256) {
    uint256 dec = 10**3;
    return (_txGasCost * dec / 74520 + 305) / dec; // Returns floor value
  }

  function getFreeStorageCost(uint256 _amount) public view returns (uint256 cost) {
    return costPerGasUnit * GAS_REFUNDED_PER_GASTOKEN * _amount;
  }
}
