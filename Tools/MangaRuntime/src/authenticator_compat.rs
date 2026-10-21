//! Source-owned HTTP authentication. The guest decides whether to retry a 401;
//! follow-ups stay on the existing bounded Swift transport and interceptor chain.
use dexvm::vm::{error::JvmError, object::Native, NatErr, NativeEntry, Vm};
use dexvm::JValue;
type R = Result<JValue, NatErr>;
const WRAPPER: &str = "Lcom/animecompanion/runtime/AuthenticatorInterceptor;";
fn call(vm: &mut Vm, value: JValue, name: &str, sig: &str, args: Vec<JValue>) -> R {
    vm.invoke_virtual_args(value, name, sig, args)
        .map_err(|e| match e {
            JvmError::Uncaught(id) => NatErr::Throw(id),
            e => NatErr::Fatal(e),
        })
}
fn basic(vm: &mut Vm, args: &[JValue]) -> R {
    use base64::Engine;
    let user = vm
        .str_of_jvalue(args[0])
        .ok_or_else(|| NatErr::Throw(vm.err_npe()))?;
    let password = vm
        .str_of_jvalue(args[1])
        .ok_or_else(|| NatErr::Throw(vm.err_npe()))?;
    let text = format!("{user}:{password}");
    if text.len() > 65_536 || vm.budget <= text.len() as i64 {
        return Err(NatErr::Fatal(JvmError::BudgetExceeded));
    }
    vm.budget -= text.len() as i64 + 1;
    let charset = if args.len() == 2 || args.get(3).is_some_and(|v| v.as_int() & 4 != 0) {
        "ISO8859_1".to_owned()
    } else {
        vm.str_of_jvalue(args[2])
            .ok_or_else(|| NatErr::Throw(vm.err_npe()))?
    };
    let bytes = match charset
        .to_ascii_uppercase()
        .replace(['-', '_'], "")
        .as_str()
    {
        "UTF8" => text.into_bytes(),
        "ISO88591" | "LATIN1" => text
            .chars()
            .map(|c| u8::try_from(c as u32).unwrap_or(b'?'))
            .collect(),
        "USASCII" | "ASCII" => text
            .chars()
            .map(|c| if (c as u32) <= 127 { c as u8 } else { b'?' })
            .collect(),
        _ => return Err(NatErr::Throw(vm.err_iae("Unsupported credentials charset"))),
    };
    Ok(vm.alloc_string(&format!("Basic {}", super::STANDARD.encode(bytes))))
}
fn configure(vm: &mut Vm, args: &[JValue]) -> R {
    if args[1].is_null_ref() {
        return Err(NatErr::Throw(vm.err_npe()));
    }
    let wrapper = vm
        .alloc_native(WRAPPER, Native::Opaque)
        .map_err(NatErr::Fatal)?;
    vm.arena.objects[wrapper.as_obj() as usize].fields = vec![args[1]];
    let Some(Native::OkHttpBuilder {
        mut interceptors,
        network_interceptors,
    }) = vm.payload_of(args[0])
    else {
        return Err(NatErr::Throw(vm.err_iae("Expected an HTTP client builder")));
    };
    interceptors.retain(|v| match v {
        JValue::Obj(id) => {
            vm.str_of(vm.classes[vm.arena.objects[*id as usize].class as usize].descriptor)
                != WRAPPER
        }
        _ => true,
    });
    interceptors.push(wrapper);
    vm.arena.objects[args[0].as_obj() as usize].native = Some(Native::OkHttpBuilder {
        interceptors,
        network_interceptors,
    });
    Ok(args[0])
}
fn intercept(vm: &mut Vm, args: &[JValue]) -> R {
    let auth = vm.arena.objects[args[0].as_obj() as usize].fields[0];
    let chain = args[1];
    let request = call(vm, chain, "request", "()Lokhttp3/Request;", vec![])?;
    let mut response = call(
        vm,
        chain,
        "proceed",
        "(Lokhttp3/Request;)Lokhttp3/Response;",
        vec![request],
    )?;
    for _ in 0..8 {
        let code = call(vm, response, "code", "()I", vec![])?.as_int();
        if code != 401 {
            return Ok(response);
        }
        let next = call(
            vm,
            auth,
            "authenticate",
            "(Lokhttp3/Route;Lokhttp3/Response;)Lokhttp3/Request;",
            vec![JValue::Null, response],
        )?;
        if next.is_null_ref() {
            return Ok(response);
        }
        call(vm, response, "close", "()V", vec![])?;
        response = call(
            vm,
            chain,
            "proceed",
            "(Lokhttp3/Request;)Lokhttp3/Response;",
            vec![next],
        )?;
    }
    Err(NatErr::Throw(vm.throwable_of(
        "Ljava/io/IOException;",
        "Authentication follow-up limit exceeded",
    )))
}
pub(super) fn install(vm: &mut Vm) -> Result<(), JvmError> {
    for (name,sig) in [("basic","(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;"),("basic","(Ljava/lang/String;Ljava/lang/String;Ljava/nio/charset/Charset;)Ljava/lang/String;"),("basic$default","(Ljava/lang/String;Ljava/lang/String;Ljava/nio/charset/Charset;ILjava/lang/Object;)Ljava/lang/String;")] {
        vm.register_native(NativeEntry{class:"Lokhttp3/Credentials;",name,sig,instance:false,f:basic})?;
    }
    let interface = super::kotlin_type_compat::marker(vm, "Lokhttp3/Authenticator;");
    vm.register_native(NativeEntry {
        class: "Lokhttp3/Authenticator;",
        name: "authenticate",
        sig: "(Lokhttp3/Route;Lokhttp3/Response;)Lokhttp3/Request;",
        instance: true,
        f: super::abstract_function,
    })?;
    vm.classes[interface as usize].is_interface = true;
    vm.register_native(NativeEntry {
        class: "Lokhttp3/OkHttpClient$Builder;",
        name: "authenticator",
        sig: "(Lokhttp3/Authenticator;)Lokhttp3/OkHttpClient$Builder;",
        instance: true,
        f: configure,
    })?;
    vm.register_native(NativeEntry {
        class: WRAPPER,
        name: "intercept",
        sig: "(Lokhttp3/Interceptor$Chain;)Lokhttp3/Response;",
        instance: true,
        f: intercept,
    })?;
    let wrapper = vm.ensure_class_by_desc(WRAPPER)?;
    let interceptor = vm.ensure_class_by_desc("Lokhttp3/Interceptor;")?;
    vm.classes[wrapper as usize].interfaces.push(interceptor);
    Ok(())
}
