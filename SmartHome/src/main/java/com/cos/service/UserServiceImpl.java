package com.cos.service;

import java.util.List;

import javax.inject.Inject;

import org.springframework.stereotype.Service;

import com.cos.domain.UserVO;
import com.cos.persistence.UserDAO;

@Service
public class UserServiceImpl implements UserService{

	@Inject
	private UserDAO dao;
	
	@Override
	public UserVO select(String userID) throws Exception {
		return dao.select(userID);
	}


	@Override
	public UserVO check(UserVO user) throws Exception {
	 return dao.check(user);
	}

	@Override
	public void insert(UserVO user) throws Exception {
		dao.insert(user);
		
	}

	@Override
	public void update(UserVO user) throws Exception {
		dao.update(user);
		
	}


	@Override
	public void delete(String userID) throws Exception {
		dao.delete(userID);
		
	}

	@Override
	public List<UserVO> account() throws Exception {
		return dao.account();
	}
	
}
