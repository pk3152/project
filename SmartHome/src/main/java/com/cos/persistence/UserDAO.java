package com.cos.persistence;

import java.util.List;

import com.cos.domain.UserVO;

public interface UserDAO {
	public UserVO select(String userID) throws Exception;
	public UserVO check(UserVO user) throws Exception;
	public void insert(UserVO user) throws Exception;
	public void update(UserVO user) throws Exception;
	public void delete(String userID) throws Exception;
	public List<UserVO> account() throws Exception;
}
