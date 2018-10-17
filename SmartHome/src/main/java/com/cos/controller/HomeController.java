package com.cos.controller;

import java.text.DateFormat;
import java.util.Date;
import java.util.List;
import java.util.Locale;

import javax.inject.Inject;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpSession;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestMethod;
import org.springframework.web.bind.annotation.RequestParam;

import com.cos.domain.UserVO;
import com.cos.service.UserService;

@Controller
public class HomeController {
	
	@Inject
	private UserService userService;
	
	
	@RequestMapping(value = "/", method = RequestMethod.GET)
	public String home() {
		return "home";
	}
	
	@RequestMapping(value = "/join", method = RequestMethod.POST)
	public String join(Model model, UserVO user,HttpSession session) throws Exception{
		System.out.println(user.getUserEmail());
		userService.insert(user);
		session.setAttribute("userID", user.getUserID());
		model.addAttribute("msg", "회원가입이 되었습니다.");
	    model.addAttribute("url", "/SmartHome/");
	    return "popup/alert";
	}
	
	@RequestMapping(value = "/login", method = RequestMethod.POST)
	public String login(Model model,UserVO user, HttpSession session)  throws Exception {
		if(session.getAttribute("userID") != null) {
			  model.addAttribute("msg", "이미 로그인되어있습니다.");
			  model.addAttribute("url", "/SmartHome/");
			  return "popup/alert";
		}else {
			
			UserVO vo = userService.check(user);
			
			if(vo == null) {
			    model.addAttribute("msg", "아이디 또는 비밀번호가 틀렸습니다.");
			    model.addAttribute("url", "/SmartHome/");
			    return "popup/alert";
			}else {
				session.setAttribute("userID", user.getUserID());
				model.addAttribute("msg", "로그인 되었습니다.");
			    model.addAttribute("url", "/SmartHome/");
			    return "popup/alert";
			}
			
		}

	}
	
	
	@RequestMapping(value = "/logout", method = RequestMethod.GET)
	public String logout(Model model, HttpSession session)  throws Exception{				
	    session.invalidate(); // 세션삭제
	    model.addAttribute("msg", "로그아웃 되었습니다.");
	    model.addAttribute("url", "/SmartHome/");
	    return "popup/alert";
	}
	
	@RequestMapping(value = "/userView", method = RequestMethod.GET)
	public String search(Model model,HttpSession session) throws Exception{

		if(session.getAttribute("userID") == null) {
			model.addAttribute("msg", "로그인이 필요합니다.");
		    model.addAttribute("url", "/SmartHome/#login");
			return "popup/alert";
		}else {
			String userID = session.getAttribute("userID").toString();
			UserVO user = userService.select(userID);
			session.setAttribute("userName",user.getUserName());
			session.setAttribute("userEmain",user.getUserEmail());
			session.setAttribute("userJoinDate",user.getJoinDate());
			return "redirect:/#userView";
		}
		

	}
	
	@RequestMapping(value = "/adminView", method = RequestMethod.GET)
	public String adminView(Model model,HttpSession session, @RequestParam String id) throws Exception{
		System.out.println(session.getAttribute("userID"));
		if(!(session.getAttribute("userID").equals("admin"))) {
			model.addAttribute("msg", "관리자만 접근이 가능합니다.");
		    model.addAttribute("url", "/SmartHome/");
			return "popup/alert";
		}else {
			UserVO user = userService.select(id);
			session.setAttribute("uID",user.getUserID());
			session.setAttribute("userName",user.getUserName());
			session.setAttribute("userEmain",user.getUserEmail());
			session.setAttribute("userJoinDate",user.getJoinDate());
			return "redirect:/userAccount#adminView";
		}
		

	}
	
	@RequestMapping(value = "/userAccount", method = RequestMethod.GET)
	public String userAccount(Model model,String userID)  throws Exception{				
	    List<UserVO> list = userService.account();
	    model.addAttribute("list", list);
	    return "userAccount";
	}
	
	@RequestMapping(value = "/update", method = RequestMethod.POST)
	public String logout(Model model, HttpSession session, UserVO user)  throws Exception{
		if(!(session.getAttribute("userID").equals("admin"))) {
	    userService.update(user);
	    model.addAttribute("msg", "회원정보가 수정되었습니다.");
	    model.addAttribute("url", "/SmartHome/");
	    return "popup/alert";
		} else {
			userService.update(user);
			model.addAttribute("msg", "회원정보수정이 완료되었습니다.");
		    model.addAttribute("url", "/SmartHome/userAccount");
		    return "popup/alert";
		}
	}

	@RequestMapping(value = "/userDelete", method = RequestMethod.GET)
	public String delete(Model model, HttpSession session, @RequestParam String userID)  throws Exception{				
	    userService.delete(userID);
	    if(!(session.getAttribute("userID").equals("admin"))) {
	    session.invalidate();
	    model.addAttribute("msg", "회원탈퇴가 완료되었습니다.");
	    model.addAttribute("url", "/SmartHome/");
	    return "popup/alert";
	    } else {
	    	model.addAttribute("msg", "회원탈퇴가 완료되었습니다.");
		    model.addAttribute("url", "/SmartHome/userAccount");
		    return "popup/alert";
	    }
	}

	
}
