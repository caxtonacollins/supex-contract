// # SPDX-License-Identifier: MIT
// %lang starknet

// mod contracts::Supex;
// use contracts::Supex::{Supex, TicketStatus, Ticket};
// use starknet::testing::Contract;
// use starknet::testing::start_test;
// use core::assert;

// #[test]
// fn test_ticket_lifecycle() {
//     start_test();
//     let mut contract = Supex::deploy();
//     let shop_owner = Contract::new();
//     contract.register_shop_owner(shop_details=1).invoke(caller_address=shop_owner.address());
//     assert(contract.verify_shop_owner(shop_owner.address()) == true, 'Shop owner should be
//     verified');

//     let customer_phone = 0x456;
//     let gadget_type = 1;
//     let estimated_duration = 100u64;
//     let ticket_id = contract.create_ticket(customer_phone, gadget_type,
//     estimated_duration).invoke(caller_address=shop_owner.address());
//     let ticket = contract.get_ticket_details(ticket_id);
//     assert(ticket.ticket_id == ticket_id, 'Ticket ID mismatch');
//     assert(ticket.status == TicketStatus::Pending, 'Status should be Pending');

//     contract.process_payment(ticket_id).invoke(caller_address=shop_owner.address());
//     let ticket = contract.get_ticket_details(ticket_id);
//     assert(ticket.status == TicketStatus::Charging, 'Status should be Charging');
//     assert(ticket.escrowed == true, 'Escrowed should be true');

//     contract.update_ticket_status(ticket_id,
//     TicketStatus::Ready).invoke(caller_address=shop_owner.address());
//     let ticket = contract.get_ticket_details(ticket_id);
//     assert(ticket.status == TicketStatus::Ready, 'Status should be Ready');

//     contract.update_ticket_status(ticket_id,
//     TicketStatus::Collected).invoke(caller_address=shop_owner.address());
//     let ticket = contract.get_ticket_details(ticket_id);
//     assert(ticket.status == TicketStatus::Collected, 'Status should be Collected');

//     contract.release_payment(ticket_id).invoke(caller_address=shop_owner.address());
//     let ticket = contract.get_ticket_details(ticket_id);
//     assert(ticket.escrowed == false, 'Escrowed should be false');
// }

// #[test]
// fn test_shop_statistics() {
//     start_test();
//     let mut contract = Supex::deploy();
//     let shop_owner = Contract::new();
//     contract.register_shop_owner(shop_details=2).invoke(caller_address=shop_owner.address());
//     let (tickets, revenue) = contract.get_shop_statistics(shop_owner.address());
//     assert(tickets == 0u64, 'Tickets should be 0');
//     assert(revenue == 0u128, 'Revenue should be 0');
// }

// #[test]
// fn test_pause_unpause() {
//     start_test();
//     let mut contract = Supex::deploy();
//     contract.pause().invoke();
//     let shop_owner = Contract::new();
//     let result = contract.create_ticket(0x1, 1,
//     10).try_invoke(caller_address=shop_owner.address());
//     assert(result.is_err(), 'Should fail when paused');
//     contract.unpause().invoke();
//     contract.register_shop_owner(shop_details=1).invoke(caller_address=shop_owner.address());
//     let result = contract.create_ticket(0x1, 1,
//     10).try_invoke(caller_address=shop_owner.address());
//     assert(result.is_ok(), 'Should succeed when unpaused');
// }
