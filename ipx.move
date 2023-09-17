module ipx::management {
    use std::signer;
    use std::error;
    use std::string::{Self, String};
    use std::option::{Self, Option};
    use aptos_token_objects::collection;
    use aptos_token_objects::token;
    use aptos_framework::object::{Self, Object};
    use aptos_framework::account;
    use aptos_framework::aptos_account;
    use aptos_framework::content;
    use aptos_framework::timestamp;

    #[test_only]
    use aptos_std::debug::print;

    const ENO_ACCESS: u64 = 100;
    const ENOT_OWNER: u64 = 101;
    const ENO_RECEIVER_ACCOUNT: u64 = 102;
    const ENOT_ADMIN: u64 = 103;
    const ENOT_VALID_key: u64 = 104;
    const ENOT_TOKEN_OWNER: u64 = 105;
    const EINALID_DATE_OVERRIDE: u64 = 106;

    #[test_only]
    const EINVALID_UPDATE: u64 = 107;

    const EMPTY_STRING: vector<u8> = b"";
    const CREATORS_COLLECTION_NAME: vector<u8> = b"CREATORS";

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct ipxConfig has key {
        admin: address,
        base_uri: String,
    }

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct ipxCreator has key {
        id: String,
        name: String,
        admin: address,
        transfer_ref: object::TransferRef,
        mutator_ref: token::MutatorRef,
        extend_ref: object::ExtendRef
    }

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct ipxcontent has key {
        id: String,
        name: String,
        start_date: u64,
        end_date: u64,
        currency: String,
        creator: Object<ipxcreator>,
        transfer_ref: object::TransferRef,
        mutator_ref: collection::MutatorRef,
        extend_ref: object::ExtendRef
    }

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct ipxkey has key {
        id: String,
        key_type_id: String,
        content: Object<ipxcontent>,
        creator: Object<ipxcreator>,
        attended_by: Option<address>,
        attended_at: u64,
        transfer_content: content::contentHandle<ipxkeyTransfercontent>,
        transfer_ref: object::TransferRef,
        mutator_ref: token::MutatorRef,
        extend_ref: object::ExtendRef
    }

    struct ipxkeyTransfercontent has drop, store {
        key_address: address,
        receiver_address: address,
        price_apt: u64, //In APT
        price: u64, //In cents. $1 = 100
        currency: String, //ISO currency code
        date: u64,
    }


/////////.../////

    fun init_module(sender: &signer) {
        let base_uri = string::utf8(b"https://nfts.kydlabs.com/a/");

        let on_chain_config = ipxConfig {
            admin: signer::address_of(sender),
            base_uri
        };
        move_to(sender, on_chain_config);

        let description = string::utf8(EMPTY_STRING);
        let name = string::utf8(CREATORS_COLLECTION_NAME);
        let uri = generate_uri_from_id(base_uri,string::utf8(CREATORS_COLLECTION_NAME));

        collection::create_unlimited_collection(
            sender,
            description,
            name,
            option::none(),
            uri,
        );
    }

    //create creator

    entry public fun create_creator(admin: &signer, creator_id: String, creator_name: String) acquires ipxConfig {
        let ipx_config_obj = is_admin(admin);

        let uri = generate_uri_from_id(ipx_config_obj.base_uri, creator_id);

        let token_constructor_ref = token::create_named_token(admin, string::utf8(CREATORS_COLLECTION_NAME), string::utf8(EMPTY_STRING), creator_id, option::none(), uri);
        let object_signer = object::generate_signer(&token_constructor_ref);
        let transfer_ref = object::generate_transfer_ref(&token_constructor_ref);
        let mutator_ref = token::generate_mutator_ref(&token_constructor_ref);
        let extend_ref = object::generate_extend_ref(&token_constructor_ref);

        object::disable_ungated_transfer(&transfer_ref);

        let creator = ipxcreator {
            id: creator_id,
            name: creator_name,
            admin: ipx_config_obj.admin,
            transfer_ref,
            mutator_ref,
            extend_ref
        };

        move_to(&object_signer, creator);
    }

// content create 

    entry public fun create_content(admin: &signer, creator: Object<ipxcreator>, content_id: String, content_name: String, currency: String, start_date: u64, end_date: u64) acquires ipxConfig {
        let ipx_config_obj = is_admin(admin);

        let uri = generate_uri_from_id(ipx_config_obj.base_uri, content_id);

        let collection_constructor_ref = collection::create_unlimited_collection(
            admin,
            string::utf8(EMPTY_STRING),
            content_id,
            option::none(),
            uri,
        );
        let object_signer = object::generate_signer(&collection_constructor_ref);
        let transfer_ref = object::generate_transfer_ref(&collection_constructor_ref);
        let mutator_ref = collection::generate_mutator_ref(&collection_constructor_ref);
        let extend_ref = object::generate_extend_ref(&collection_constructor_ref);

        object::disable_ungated_transfer(&transfer_ref);

        let content = ipxcontent {
            id: content_id,
            name: content_name,
            currency,
            start_date,
            end_date,
            creator,
            transfer_ref,
            mutator_ref,
            extend_ref
        };

        move_to(&object_signer, content);
    }

// key create

    entry public fun create_key(admin: &signer, receiver: address, content: Object<ipxcontent>, key_type_id: String, key_id: String, price_apt: u64, price: u64, date: u64)
    acquires ipxConfig, ipxcontent, ipxkey {
        let ipx_config_obj = is_admin(admin);
        let sender_addr = signer::address_of(admin);

        if(!account::exists_at(receiver)) {
            aptos_account::create_account(receiver);
        };

        let uri = generate_uri_from_id(ipx_config_obj.base_uri, key_id);

        let content_obj = borrow_global_mut<ipxcontent>(object::object_address(&content));

        let token_constructor_ref = token::create_named_token(admin, content_obj.id, string::utf8(EMPTY_STRING), key_id, option::none(), uri);
        let object_signer = object::generate_signer(&token_constructor_ref);
        let transfer_ref = object::generate_transfer_ref(&token_constructor_ref);
        let mutator_ref = token::generate_mutator_ref(&token_constructor_ref);
        let extend_ref = object::generate_extend_ref(&token_constructor_ref);

        object::disable_ungated_transfer(&transfer_ref);

        let linear_transfer_ref = object::generate_linear_transfer_ref(&transfer_ref);
        object::transfer_with_ref(linear_transfer_ref, receiver);

        let key = ipxkey {
            id: key_id,
            content,
            key_type_id,
            creator: content_obj.creator,
            attended_at: 0,
            attended_by: option::none(),
            transfer_content: object::new_content_handle(&object_signer),
            transfer_ref,
            mutator_ref,
            extend_ref
        };

        move_to(&object_signer, key);

        let purchase_date = timestamp::now_microseconds();
        if(date > 0) {
            assert!(date < timestamp::now_microseconds(), EINALID_DATE_OVERRIDE);
            purchase_date = date;
        };

        let key_obj = borrow_global_mut<ipxkey>(object::address_from_constructor_ref(&token_constructor_ref));
        content::emit_content<ipxkeyTransfercontent>(
            &mut key_obj.transfer_content,
            ipxkeyTransfercontent {
                key_address: generate_key_address(sender_addr, content_obj.id, key_id),
                receiver_address: receiver,
                price_apt,
                price,
                currency: content_obj.currency,
                date: purchase_date
            }
        );
    }
// 



// key transfer
    entry public fun transfer_key(admin: &signer, receiver: address, key: Object<ipxkey>, price_apt: u64, price: u64) acquires ipxConfig, ipxkey, ipxcontent {
        is_admin(admin);

        if(!account::exists_at(receiver)) {
            aptos_account::create_account(receiver);
        };

        let key_obj = borrow_global_mut<ipxkey>(object::object_address(&key));
        let linear_transfer_ref = object::generate_linear_transfer_ref(&key_obj.transfer_ref);
        object::transfer_with_ref(linear_transfer_ref, receiver);

        let content_obj = borrow_global<ipxcontent>(object::object_address(&key_obj.content));

        content::emit_content<ipxkeyTransfercontent>(
            &mut key_obj.transfer_content,
            ipxkeyTransfercontent {
                key_address: object::object_address(&key),
                receiver_address: receiver,
                price_apt,
                price,
                currency: content_obj.currency,
                date: timestamp::now_microseconds()
            }
        );
    }


// redeem key
    entry public fun redeem_key(admin: &signer, key: Object<ipxkey>) acquires ipxConfig, ipxkey {
        is_admin(admin);

        let key_obj = borrow_global_mut<ipxkey>(object::object_address(&key));

        let owner_addr = object::owner(key);
        let attended_by = &mut key_obj.attended_by;
        option::fill(attended_by, owner_addr);
        key_obj.attended_at = timestamp::now_microseconds();
    }

    entry public fun update_creator_uri(admin: &signer, creator: Object<ipxcreator>) acquires ipxConfig, ipxcreator {
        let ipx_config_obj = is_admin(admin);

        let creator_obj = borrow_global_mut<ipxcreator>(object::object_address(&creator));
        let uri = generate_uri_from_id(ipx_config_obj.base_uri, creator_obj.id);

        token::set_uri(&creator_obj.mutator_ref, uri);
    }

    entry public fun update_content_uri(admin: &signer, ipx_content: Object<ipxcontent>) acquires ipxConfig, ipxcontent {
        let ipx_config_obj = is_admin(admin);

        let content_obj = borrow_global_mut<ipxcontent>(object::object_address(&ipx_content));
        let uri = generate_uri_from_id(ipx_config_obj.base_uri, content_obj.id);

        collection::set_uri(&content_obj.mutator_ref, uri);
    }

    entry public fun update_key_uri(admin: &signer, ipx_content: Object<ipxkey>) acquires ipxConfig, ipxkey {
        let ipx_config_obj = is_admin(admin);

        let key_obj = borrow_global_mut<ipxkey>(object::object_address(&ipx_content));
        let uri = generate_uri_from_id(ipx_config_obj.base_uri, key_obj.id);

        token::set_uri(&key_obj.mutator_ref, uri);
    }

    entry public fun update_content_name(admin: &signer, ipx_content: Object<ipxcontent>, name: String) acquires ipxConfig, ipxcontent {
        is_admin(admin);

        let content_obj = borrow_global_mut<ipxcontent>(object::object_address(&ipx_content));
        content_obj.name = name;
    }

    entry public fun update_content_start_date(admin: &signer, ipx_content: Object<ipxcontent>, start_date: u64) acquires ipxConfig, ipxcontent {
        is_admin(admin);

        let content_obj = borrow_global_mut<ipxcontent>(object::object_address(&ipx_content));
        content_obj.start_date = start_date;
    }

    entry public fun update_content_end_date(admin: &signer, ipx_content: Object<ipxcontent>, end_date: u64) acquires ipxConfig, ipxcontent {
        is_admin(admin);

        let content_obj = borrow_global_mut<ipxcontent>(object::object_address(&ipx_content));
        content_obj.end_date = end_date;
    }

    entry public fun update_creator_name(admin: &signer, creator: Object<ipxcreator>, name: String) acquires ipxConfig, ipxcreator {
        is_admin(admin);

        let creator_obj = borrow_global_mut<ipxcreator>(object::object_address(&creator));
        creator_obj.name = name;
    }

    inline fun is_admin(admin: &signer): &ipxConfig {
        let admin_addr = signer::address_of(admin);
        let ipx_config_obj = borrow_global<ipxConfig>(admin_addr);
        assert!(ipx_config_obj.admin == admin_addr, error::permission_denied(ENOT_ADMIN));

        ipx_config_obj
    }

    public fun validate_key(content: Object<ipxcontent>, key: Object<ipxkey>) acquires ipxkey, ipxcontent {
        let key_obj = borrow_global<ipxkey>(object::object_address(&key));
        let key_content_obj = borrow_global<ipxcontent>(object::object_address(&key_obj.content));
        let content_obj = borrow_global<ipxcontent>(object::object_address(&content));

        assert!(
            content_obj.id == key_content_obj.id,
            error::permission_denied(ENOT_VALID_key),
        );
    }

    fun generate_uri_from_id(base_uri: String, id: String): String {
        let base_uri_bytes = string::bytes(&base_uri);
        let uri = string::utf8(*base_uri_bytes);
        string::append(&mut uri, id);
        string::append_utf8(&mut uri, b"/metadata.json");

        uri
    }

    fun generate_key_address(creator_address: address, content_id: String, key_id: String): address {
        token::create_token_address(
            &creator_address,
            &content_id,
            &key_id
        )
    }

    fun generate_content_address(creator_address: address, content_id: String): address {
        collection::create_collection_address(
            &creator_address,
            &content_id,
        )
    }

    fun generate_creator_address(creator_address: address, creator_id: String): address {
        token::create_token_address(
            &creator_address,
            &string::utf8(CREATORS_COLLECTION_NAME),
            &creator_id
        )
    }

    #[view]
    fun view_creator(creator_address: address, creator_id: String): ipxcreator acquires ipxcreator {
        let token_address = generate_creator_address(creator_address, creator_id);
        move_from<ipxcreator>(token_address)
    }

    #[view]
    fun view_content(creator_address: address, content_id: String): ipxcontent acquires ipxcontent {
        let collection_address = generate_content_address(creator_address, content_id);
        move_from<ipxcontent>(collection_address)
    }

    #[view]
    fun view_key(creator_address: address, content_id: String, key_id: String): ipxkey acquires ipxkey {
        let token_address = generate_key_address(creator_address, content_id, key_id);
        move_from<ipxkey>(token_address)
    }

    #[test_only]
    fun init_module_for_test(creator: &signer, aptos_framework: &signer) {
        account::create_account_for_test(signer::address_of(creator));
        init_module(creator);

        timestamp::set_time_has_started_for_testing(aptos_framework);
        timestamp::update_global_time_for_test(1691941413632);
    }

    #[test(account = @0xFA, user = @0xFF, aptos_framework = @aptos_framework)]
    #[expected_failure]
    fun test_auth(account: &signer, aptos_framework: &signer, user: &signer) acquires ipxConfig {
        init_module_for_test(account, aptos_framework);
        aptos_account::create_account(signer::address_of(user));

        create_creator(
            user, string::utf8(b"ORG_ID"), string::utf8(b"ORG_NAME")
        );
    }

    #[test(account = @0x7a82477da5e3dc93eec06410198ae66371cc06e0665b9f97074198e85e67d53b, user = @0xFF, transfer_receiver = @0xFB, aptos_framework = @aptos_framework)]
    fun test_create_key(account: &signer, aptos_framework: &signer, user: &signer, transfer_receiver: address) acquires ipxConfig, ipxcreator, ipxcontent, ipxkey {
        init_module_for_test(account, aptos_framework);

        create_creator(
            account, string::utf8(b"OR87c35334-d43c-4208-b8dd-7adeab94a6d5"), string::utf8(b"ORG_NAME")
        );

        let account_address = signer::address_of(account);
        let creator_address = generate_creator_address(account_address, string::utf8(b"OR87c35334-d43c-4208-b8dd-7adeab94a6d5"));
        assert!(object::is_object(creator_address), 400);
        print(&token::create_token_seed(&string::utf8(CREATORS_COLLECTION_NAME), &string::utf8(b"OR87c35334-d43c-4208-b8dd-7adeab94a6d5")));
        print(&creator_address);
        update_creator_uri(account, object::address_to_object<ipxcreator>(creator_address));

        create_content(
            account, object::address_to_object<ipxcreator>(creator_address), string::utf8(b"content_ID"), string::utf8(b"A Test content"), string::utf8(b"USD"),1,2
        );

        let ipx_content_address = generate_content_address(account_address, string::utf8(b"content_ID"));
        create_key(account, signer::address_of(user), object::address_to_object<ipxcontent>(ipx_content_address),  string::utf8(b"TT_ID"), string::utf8(b"key_id_1"), 4, 45, 1);
        create_key(account, signer::address_of(user), object::address_to_object<ipxcontent>(ipx_content_address),  string::utf8(b"TT_ID"), string::utf8(b"key_id_2"), 4, 45, 2);
        create_key(account, signer::address_of(user), object::address_to_object<ipxcontent>(ipx_content_address),  string::utf8(b"TT_ID"), string::utf8(b"key_id_3"), 4, 45, 3);

        update_content_start_date(account, object::address_to_object<ipxcontent>(ipx_content_address), 3);
        update_content_end_date(account, object::address_to_object<ipxcontent>(ipx_content_address), 4);
        update_content_uri(account, object::address_to_object<ipxcontent>(ipx_content_address));

        let ipx_key_address = generate_key_address(account_address, string::utf8(b"content_ID"), string::utf8(b"key_id_1"));

        assert!(object::is_owner(object::address_to_object<ipxkey>(ipx_key_address), signer::address_of(user)), error::permission_denied(ENOT_TOKEN_OWNER));

        transfer_key(account, transfer_receiver, object::address_to_object<ipxkey>(ipx_key_address), 0, 0);
        assert!(object::is_owner(object::address_to_object<ipxkey>(ipx_key_address), transfer_receiver), error::permission_denied(ENOT_TOKEN_OWNER));

        redeem_key(account, object::address_to_object<ipxkey>(ipx_key_address));

        let ipx_key = borrow_global<ipxkey>(ipx_key_address);
        assert!(ipx_key.attended_at > 0, error::permission_denied(EINVALID_UPDATE));
    }
}
